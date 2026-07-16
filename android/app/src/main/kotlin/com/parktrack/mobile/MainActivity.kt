package com.parktrack.mobile

import android.content.Context
import com.yandex.mapkit.MapKitFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.parktrack.mobile/mapkit").setMethodCallHandler { call, result ->
            if (call.method == "setLocale") {
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
            } else {
                result.notImplemented()
            }
        }
    }
}
