import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../storage/location_storage.dart';

abstract interface class LocationPlatformClient {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<Position?> getLastKnownPosition();

  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  });

  Stream<Position> getPositionStream({
    required LocationSettings locationSettings,
  });
}

class GeolocatorLocationPlatformClient implements LocationPlatformClient {
  const GeolocatorLocationPlatformClient();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position?> getLastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) => Geolocator.getCurrentPosition(locationSettings: locationSettings);

  @override
  Stream<Position> getPositionStream({
    required LocationSettings locationSettings,
  }) => Geolocator.getPositionStream(locationSettings: locationSettings);
}

abstract interface class NetworkPositionSource {
  Future<Position?> getCurrentPosition();

  Stream<NetworkPositionUpdate> watchPositions();
}

class NetworkPositionUpdate {
  const NetworkPositionUpdate({required this.providerAvailable, this.position});

  final bool providerAvailable;
  final Position? position;
}

class AndroidNetworkPositionSource implements NetworkPositionSource {
  const AndroidNetworkPositionSource();

  static const _methodChannel = MethodChannel('com.parktrack.mobile/location');
  static const _eventChannel = EventChannel(
    'com.parktrack.mobile/network_location',
  );
  static final Stream<NetworkPositionUpdate> _positionStream = _eventChannel
      .receiveBroadcastStream()
      .map(_decodeUpdate);

  static NetworkPositionUpdate _decodeUpdate(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid Android network location event');
    }
    final providerAvailable = value['provider_available'] as bool? ?? true;
    final position = value.containsKey('latitude')
        ? Position.fromMap(value)
        : null;
    return NetworkPositionUpdate(
      providerAvailable: providerAvailable,
      position: position,
    );
  }

  @override
  Future<Position?> getCurrentPosition() async {
    try {
      final value = await _methodChannel.invokeMethod<Object?>(
        'getNetworkPosition',
      );
      if (value == null) return null;
      return Position.fromMap(value);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  Stream<NetworkPositionUpdate> watchPositions() => _positionStream;
}

class PreferredLocationService {
  PreferredLocationService({
    LocationPlatformClient platform = const GeolocatorLocationPlatformClient(),
    NetworkPositionSource networkSource = const AndroidNetworkPositionSource(),
    LocationPositionStorage? storage,
    LocationPositionStorage? networkStorage,
    bool? preferAndroidNetwork,
    this.networkFallbackDelay = const Duration(seconds: 5),
    this.networkTimeout = const Duration(seconds: 5),
    this.fallbackTimeout = const Duration(seconds: 5),
  }) : _platform = platform,
       _networkSource = networkSource,
       _storage = storage ?? LocationStorage(),
       _networkStorage =
           networkStorage ??
           LocationStorage(
             key: LocationStorage.lastSuccessfulNetworkLocationKey,
           ),
       _preferAndroidNetwork =
           preferAndroidNetwork ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const _fallbackStreamRetryDelay = Duration(seconds: 1);
  static const _logPrefix = '[ParkTrackLocation]';

  final LocationPlatformClient _platform;
  final NetworkPositionSource _networkSource;
  final LocationPositionStorage _storage;
  final LocationPositionStorage _networkStorage;
  final bool _preferAndroidNetwork;
  final Duration networkFallbackDelay;
  final Duration networkTimeout;
  final Duration fallbackTimeout;

  Future<Position> getCurrentPosition() async {
    await _ensureLocationAccess();

    if (_preferAndroidNetwork) {
      _debugLog('current source=android-network-first');
      return _getCurrentAndroidPosition();
    }

    Object? freshError;
    try {
      final fresh = await _platform.getCurrentPosition(
        locationSettings: LocationSettings(timeLimit: fallbackTimeout),
      );
      if (_isValid(fresh)) {
        _debugLog('current source=fused result=${_describe(fresh)}');
        await _remember(fresh);
        return fresh;
      }
    } catch (error) {
      freshError = error;
    }
    final cached = await getLastKnownPosition();
    if (cached != null) {
      _debugLog('current source=cache result=${_describe(cached)}');
      return cached;
    }
    if (freshError != null) throw freshError;
    throw const PositionUpdateException('No valid location is available');
  }

  Future<Position> _getCurrentAndroidPosition() async {
    final wait = Stopwatch()..start();
    final networkPosition = await _networkPosition();
    if (_isTrustedAndroidPosition(networkPosition)) {
      _debugLog('current source=network result=${_describe(networkPosition)}');
      await _rememberNetwork(networkPosition!);
      return networkPosition;
    }
    _debugLog('current source=network rejected=${_describe(networkPosition)}');

    final remainingGrace = networkFallbackDelay - wait.elapsed;
    if (remainingGrace > Duration.zero) {
      _debugLog(
        'current fallback=waiting remainingMs=${remainingGrace.inMilliseconds}',
      );
      await Future<void>.delayed(remainingGrace);
    }

    Object? freshError;
    try {
      final fresh = await _platform.getCurrentPosition(
        locationSettings: LocationSettings(timeLimit: fallbackTimeout),
      );
      if (_isTrustedAndroidPosition(fresh)) {
        _debugLog('current source=fused result=${_describe(fresh)}');
        await _remember(fresh);
        return fresh;
      }
    } catch (error) {
      freshError = error;
    }

    final cached = await _getAndroidFallbackPosition();
    if (cached != null) {
      _debugLog('current source=fallback-cache result=${_describe(cached)}');
      return cached;
    }
    if (freshError != null) throw freshError;
    throw const PositionUpdateException('No valid location is available');
  }

  Future<Position?> getLastKnownPosition() async {
    if (_preferAndroidNetwork) {
      try {
        final trustedNetwork = await _networkStorage.read();
        final result = _isTrustedAndroidPosition(trustedNetwork)
            ? trustedNetwork
            : null;
        _debugLog('lastKnown source=network-cache result=${_describe(result)}');
        return result;
      } catch (_) {
        _debugLog('lastKnown source=network-cache error=true');
        return null;
      }
    }

    try {
      final cached = await _platform.getLastKnownPosition();
      if (_isValid(cached)) return cached;
    } catch (_) {
      // Some browsers and devices do not expose a last-known position.
    }
    try {
      final stored = await _storage.read();
      return _isValid(stored) ? stored : null;
    } catch (_) {
      return null;
    }
  }

  Stream<Position> watchCurrentPosition({
    LocationSettings? locationSettings,
    bool preferNetworkInitialFix = false,
  }) async* {
    await _ensureLocationAccess();
    final settings =
        locationSettings ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 1,
                intervalDuration: const Duration(seconds: 2),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 1,
              ));

    if (_preferAndroidNetwork) {
      _debugLog('watch source=android-network-first');
      yield* _watchAndroidPositions(settings);
      return;
    }

    yield* _platform
        .getPositionStream(locationSettings: settings)
        .where(_isValid)
        .map((position) {
          unawaited(_remember(position));
          return position;
        });
  }

  Stream<Position> _watchAndroidPositions(LocationSettings fallbackSettings) {
    late final StreamController<Position> controller;
    StreamSubscription<NetworkPositionUpdate>? networkSubscription;
    StreamSubscription<Position>? fallbackSubscription;
    Timer? fallbackTimer;
    Timer? fallbackRetryTimer;
    var fallbackGeneration = 0;
    var fallbackActive = false;
    var hasNetworkPosition = false;
    var cancelled = false;

    Future<void> cancelFallbackSubscription() async {
      final subscription = fallbackSubscription;
      fallbackSubscription = null;
      if (subscription != null) await subscription.cancel();
    }

    void startFallback(int generation) {
      if (cancelled ||
          generation != fallbackGeneration ||
          fallbackSubscription != null) {
        return;
      }
      fallbackActive = true;
      _debugLog('watch fallback start generation=$generation');
      fallbackSubscription = _platform
          .getPositionStream(locationSettings: fallbackSettings)
          .listen(
            (position) {
              if (cancelled ||
                  !fallbackActive ||
                  generation != fallbackGeneration ||
                  !_isTrustedAndroidPosition(position)) {
                _debugLog('watch fallback rejected=${_describe(position)}');
                return;
              }
              _debugLog('watch source=fused result=${_describe(position)}');
              unawaited(_remember(position));
              if (!controller.isClosed) controller.add(position);
            },
            onError: (Object error, StackTrace stackTrace) {
              if (cancelled || generation != fallbackGeneration) return;
              _debugLog('watch fallback error=$error retry=true');
              fallbackSubscription = null;
              fallbackRetryTimer?.cancel();
              fallbackRetryTimer = Timer(_fallbackStreamRetryDelay, () {
                startFallback(generation);
              });
            },
            onDone: () {
              if (cancelled || generation != fallbackGeneration) return;
              _debugLog('watch fallback done retry=true');
              fallbackSubscription = null;
              fallbackRetryTimer?.cancel();
              fallbackRetryTimer = Timer(_fallbackStreamRetryDelay, () {
                startFallback(generation);
              });
            },
          );
    }

    void armFallback() {
      if (fallbackActive || (fallbackTimer?.isActive ?? false)) return;
      fallbackTimer?.cancel();
      fallbackRetryTimer?.cancel();
      fallbackActive = false;
      final generation = ++fallbackGeneration;
      fallbackTimer = Timer(networkFallbackDelay, () {
        _debugLog(
          'watch fallback armed reason=no_network_fix '
          'delayMs=${networkFallbackDelay.inMilliseconds}',
        );
        startFallback(generation);
      });
    }

    void onNetworkUpdate(NetworkPositionUpdate update) {
      if (cancelled) return;
      final position = update.position;
      if (_isTrustedAndroidPosition(position)) {
        _debugLog(
          'watch source=network providerAvailable=${update.providerAvailable} '
          'result=${_describe(position)}',
        );
        hasNetworkPosition = true;
        fallbackTimer?.cancel();
        fallbackRetryTimer?.cancel();
        fallbackActive = false;
        fallbackGeneration++;
        unawaited(cancelFallbackSubscription());
        unawaited(_rememberNetwork(position!));
        if (!controller.isClosed) controller.add(position);
        return;
      }

      if (!update.providerAvailable) {
        _debugLog('watch network providerAvailable=false fallback=true');
        armFallback();
        return;
      }

      if (hasNetworkPosition && !fallbackActive) {
        _debugLog('watch network silent providerAvailable=true stale=false');
        fallbackTimer?.cancel();
      }
    }

    Future<void> cancelAll() async {
      cancelled = true;
      fallbackTimer?.cancel();
      fallbackRetryTimer?.cancel();
      fallbackGeneration++;
      await networkSubscription?.cancel();
      networkSubscription = null;
      await cancelFallbackSubscription();
    }

    void start() {
      armFallback();
      networkSubscription = _networkSource.watchPositions().listen(
        onNetworkUpdate,
        onError: (Object error, StackTrace stackTrace) {
          _debugLog('watch network error=$error fallbackGraceContinues=true');
          // A silent network stream keeps the five-second GPS grace period
          // active and can recover if the Android provider resumes.
        },
      );
    }

    controller = StreamController<Position>(
      onListen: start,
      onCancel: cancelAll,
    );
    return controller.stream;
  }

  Future<void> _ensureLocationAccess() async {
    final serviceEnabled = await _platform.isLocationServiceEnabled();
    _debugLog('access serviceEnabled=$serviceEnabled');
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await _platform.checkPermission();
    _debugLog('access permission=$permission');
    if (permission == LocationPermission.denied) {
      permission = await _platform.requestPermission();
      _debugLog('access requestedPermission=$permission');
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException(null);
    }
  }

  Future<Position?> _networkPosition() async {
    try {
      return await _networkSource.getCurrentPosition().timeout(
        networkTimeout,
        onTimeout: () {
          _debugLog(
            'network oneShot timeoutMs=${networkTimeout.inMilliseconds}',
          );
          return null;
        },
      );
    } catch (error) {
      _debugLog('network oneShot error=$error');
      return null;
    }
  }

  Future<Position?> _getAndroidFallbackPosition() async {
    try {
      final networkCached = await _networkStorage.read();
      if (_isTrustedAndroidPosition(networkCached)) return networkCached;
    } catch (_) {
      // Continue with the explicitly allowed GPS fallback caches.
    }
    try {
      final systemCached = await _platform.getLastKnownPosition();
      if (_isTrustedAndroidPosition(systemCached)) return systemCached;
    } catch (_) {
      // Some devices do not expose a last-known position.
    }
    try {
      final stored = await _storage.read();
      return _isTrustedAndroidPosition(stored) ? stored : null;
    } catch (_) {
      return null;
    }
  }

  bool _isValid(Position? position) {
    if (position == null) return false;
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude >= -90 &&
        position.latitude <= 90 &&
        position.longitude >= -180 &&
        position.longitude <= 180;
  }

  bool _isTrustedAndroidPosition(Position? position) =>
      _isValid(position) && !position!.isMocked;

  Future<void> _rememberNetwork(Position position) async {
    await Future.wait([_remember(position), _write(_networkStorage, position)]);
  }

  Future<void> _remember(Position position) => _write(_storage, position);

  Future<void> _write(
    LocationPositionStorage storage,
    Position position,
  ) async {
    try {
      await storage.write(position);
    } catch (_) {
      // Persisting a fallback must never make a valid live fix fail.
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('$_logPrefix $message');
  }

  String _describe(Position? position) {
    if (position == null) return 'null';
    final ageMs = DateTime.now().difference(position.timestamp).inMilliseconds;
    return 'lat=${position.latitude.toStringAsFixed(6)} '
        'lon=${position.longitude.toStringAsFixed(6)} '
        'accuracy=${position.accuracy.toStringAsFixed(1)} '
        'timestamp=${position.timestamp.toIso8601String()} ageMs=$ageMs '
        'mocked=${position.isMocked} valid=${_isValid(position)} '
        'trusted=${_isTrustedAndroidPosition(position)}';
  }
}
