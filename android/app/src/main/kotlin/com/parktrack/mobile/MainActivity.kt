package com.parktrack.mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.yandex.mapkit.MapKitFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private var headingSensorManager: SensorManager? = null
    private var headingSensor: Sensor? = null
    private var headingSink: EventChannel.EventSink? = null
    private var lastHeading: Double? = null
    private var lastHeadingEmittedAt = 0L
    private var networkLocationManager: LocationManager? = null
    private var networkLocationListener: LocationListener? = null

    private val headingListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val heading = headingFromRotationVector(event.values) ?: return
            val previous = lastHeading
            val now = SystemClock.elapsedRealtime()
            if (
                previous != null &&
                circularDifference(previous, heading) < MIN_HEADING_CHANGE_DEGREES &&
                now - lastHeadingEmittedAt < HEADING_EMIT_INTERVAL_MS
            ) {
                return
            }
            lastHeading = heading
            lastHeadingEmittedAt = now
            headingSink?.success(heading)
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.parktrack.mobile/mapkit",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setLocale" -> {
                    val locale = call.argument<String>("locale")
                    if (locale != null) {
                        // Save locale for the next startup
                        val prefs = getSharedPreferences("app_settings", Context.MODE_PRIVATE)
                        prefs.edit().putString("map_locale", locale).apply()

                        // We don't call setLocale here to avoid crashes if already initialized.
                        // The user will be notified that a restart is required.
                        result.success(null)
                    } else {
                        result.error("INVALID_LOCALE", "Locale is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.parktrack.mobile/location",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNetworkPosition" -> getNetworkPosition(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.parktrack.mobile/network_location",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                startNetworkLocationUpdates(events)
            }

            override fun onCancel(arguments: Any?) {
                stopNetworkLocationUpdates()
            }
        })

        headingSensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        headingSensor = headingSensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: headingSensorManager?.getDefaultSensor(
                Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR,
            )
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.parktrack.mobile/heading",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                stopHeadingUpdates()
                headingSink = events
                val sensor = headingSensor
                if (sensor == null) {
                    events.error("HEADING_UNAVAILABLE", "No rotation-vector sensor", null)
                    return
                }
                headingSensorManager?.registerListener(
                    headingListener,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME,
                )
            }

            override fun onCancel(arguments: Any?) {
                stopHeadingUpdates()
            }
        })
    }

    override fun onDestroy() {
        stopNetworkLocationUpdates()
        stopHeadingUpdates()
        super.onDestroy()
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun startNetworkLocationUpdates(events: EventChannel.EventSink) {
        stopNetworkLocationUpdates()
        if (!hasLocationPermission()) {
            locationLog("stream permission=denied")
            events.error("PERMISSION_DENIED", "Location permission is not granted", null)
            return
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val hasNetworkProvider = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.hasProvider(LocationManager.NETWORK_PROVIDER)
        } else {
            manager.allProviders.contains(LocationManager.NETWORK_PROVIDER)
        }
        if (!hasNetworkProvider) {
            locationLog("stream provider=network available=false reason=missing")
            events.error("NETWORK_PROVIDER_UNAVAILABLE", "Network provider is unavailable", null)
            return
        }

        networkLocationManager = manager
        val providerEnabled =
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        locationLog("stream provider=network enabled=$providerEnabled")
        events.success(
            mapOf(
                "provider_available" to providerEnabled,
            ),
        )
        val cached = try {
            manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        } catch (_: SecurityException) {
            null
        }
        if (
            providerEnabled &&
            cached != null &&
            abs(System.currentTimeMillis() - cached.time) <= NETWORK_CACHE_MAX_AGE_MS
        ) {
            locationLog("stream source=network-cache result=${cached.describeForLog()}")
            events.success(cached.toChannelMap())
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationLog("stream source=network result=${location.describeForLog()}")
                events.success(location.toChannelMap())
            }

            override fun onProviderDisabled(provider: String) {
                locationLog("stream provider=$provider enabled=false")
                events.success(mapOf("provider_available" to false))
            }

            override fun onProviderEnabled(provider: String) {
                locationLog("stream provider=$provider enabled=true")
                events.success(mapOf("provider_available" to true))
            }
        }
        networkLocationListener = listener

        try {
            manager.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER,
                NETWORK_UPDATE_INTERVAL_MS,
                NETWORK_UPDATE_MIN_DISTANCE_METERS,
                listener,
                Looper.getMainLooper(),
            )
        } catch (_: SecurityException) {
            locationLog("stream error=permission_denied")
            stopNetworkLocationUpdates()
            events.error("PERMISSION_DENIED", "Location permission is not granted", null)
        } catch (_: IllegalArgumentException) {
            locationLog("stream error=network_provider_unavailable")
            stopNetworkLocationUpdates()
            events.error(
                "NETWORK_PROVIDER_UNAVAILABLE",
                "Network provider is unavailable",
                null,
            )
        }
    }

    private fun stopNetworkLocationUpdates() {
        val manager = networkLocationManager
        val listener = networkLocationListener
        if (manager != null && listener != null) {
            try {
                manager.removeUpdates(listener)
            } catch (_: SecurityException) {
                // The permission can be revoked while the stream is active.
            }
        }
        networkLocationListener = null
        networkLocationManager = null
    }

    private fun stopHeadingUpdates() {
        headingSensorManager?.unregisterListener(headingListener)
        headingSink = null
        lastHeading = null
        lastHeadingEmittedAt = 0L
    }

    @Suppress("DEPRECATION")
    private fun currentDisplayRotation(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            windowManager.defaultDisplay.rotation
        }
    }

    private fun headingFromRotationVector(rotationVector: FloatArray): Double? {
        val rotationMatrix = FloatArray(9)
        val adjustedMatrix = FloatArray(9)
        val orientation = FloatArray(3)
        SensorManager.getRotationMatrixFromVector(rotationMatrix, rotationVector)
        val axes = when (currentDisplayRotation()) {
            Surface.ROTATION_90 ->
                SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 ->
                SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 ->
                SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        if (!SensorManager.remapCoordinateSystem(
                rotationMatrix,
                axes.first,
                axes.second,
                adjustedMatrix,
            )
        ) {
            return null
        }
        SensorManager.getOrientation(adjustedMatrix, orientation)
        val degrees = Math.toDegrees(orientation[0].toDouble())
        return ((degrees % 360) + 360) % 360
    }

    private fun circularDifference(first: Double, second: Double): Double {
        val difference = abs(first - second) % 360
        return minOf(difference, 360 - difference)
    }

    @Suppress("DEPRECATION")
    private fun getNetworkPosition(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            locationLog("oneShot permission=denied")
            result.error("PERMISSION_DENIED", "Location permission is not granted", null)
            return
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (!manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            locationLog("oneShot provider=network enabled=false result=null")
            result.success(null)
            return
        }

        val cached = try {
            manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        } catch (_: SecurityException) {
            null
        }
        if (
            cached != null &&
            abs(System.currentTimeMillis() - cached.time) <= NETWORK_CACHE_MAX_AGE_MS
        ) {
            locationLog("oneShot source=network-cache result=${cached.describeForLog()}")
            result.success(cached.toChannelMap())
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var completed = false
        lateinit var listener: LocationListener
        lateinit var timeout: Runnable

        fun complete(location: Location?) {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            manager.removeUpdates(listener)
            locationLog("oneShot source=network result=${location?.describeForLog() ?: "null"}")
            result.success(location?.toChannelMap())
        }

        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                complete(location)
            }

            override fun onProviderDisabled(provider: String) {
                complete(null)
            }
        }
        timeout = Runnable { complete(null) }

        try {
            handler.postDelayed(timeout, NETWORK_REQUEST_TIMEOUT_MS)
            manager.requestSingleUpdate(
                LocationManager.NETWORK_PROVIDER,
                listener,
                Looper.getMainLooper(),
            )
        } catch (_: SecurityException) {
            locationLog("oneShot error=permission_denied")
            complete(null)
        } catch (_: IllegalArgumentException) {
            locationLog("oneShot error=network_provider_unavailable")
            complete(null)
        }
    }

    private fun locationLog(message: String) {
        if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.d("ParkTrackLocation", "[ParkTrackLocation] $message")
        }
    }

    private fun Location.describeForLog(): String {
        val mocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            isMock
        } else {
            isFromMockProvider
        }
        val ageMs = System.currentTimeMillis() - time
        return "lat=${"%.6f".format(latitude)} lon=${"%.6f".format(longitude)} " +
            "accuracy=${"%.1f".format(accuracy)} timestamp=$time ageMs=$ageMs " +
            "mocked=$mocked provider=$provider"
    }

    private fun Location.toChannelMap(): Map<String, Any?> {
        val verticalAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            verticalAccuracyMeters.toDouble()
        } else {
            0.0
        }
        val bearingAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            bearingAccuracyDegrees.toDouble()
        } else {
            0.0
        }
        val speedAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            speedAccuracyMetersPerSecond.toDouble()
        } else {
            0.0
        }
        val mocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            isMock
        } else {
            isFromMockProvider
        }

        return mapOf(
            "provider_available" to true,
            "latitude" to latitude,
            "longitude" to longitude,
            "timestamp" to time,
            "accuracy" to accuracy.toDouble(),
            "altitude" to altitude,
            "altitude_accuracy" to verticalAccuracy,
            "heading" to bearing.toDouble(),
            "heading_accuracy" to bearingAccuracy,
            "speed" to speed.toDouble(),
            "speed_accuracy" to speedAccuracy,
            "is_mocked" to mocked,
        )
    }

    companion object {
        private const val NETWORK_CACHE_MAX_AGE_MS = 30_000L
        private const val NETWORK_REQUEST_TIMEOUT_MS = 3_500L
        private const val NETWORK_UPDATE_INTERVAL_MS = 1_000L
        private const val NETWORK_UPDATE_MIN_DISTANCE_METERS = 1F
        private const val HEADING_EMIT_INTERVAL_MS = 16L
        private const val MIN_HEADING_CHANGE_DEGREES = 0.25
    }
}
