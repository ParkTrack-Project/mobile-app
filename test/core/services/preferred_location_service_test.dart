import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/core/services/preferred_location_service.dart';
import 'package:mobile/core/storage/location_storage.dart';

void main() {
  const grace = Duration(milliseconds: 40);

  test('returns Android network position without calling GPS', () async {
    final platform = _FakeLocationPlatform(current: _position(2, 2));
    final networkStorage = _FakeLocationStorage();
    final network = _FakeNetworkSource(position: _position(1, 1));
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: networkStorage,
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );

    final result = await service.getCurrentPosition();

    expect(result, _position(1, 1));
    expect(network.currentCalls, 1);
    expect(platform.currentCalls, 0);
    expect(platform.lastKnownCalls, 0);
    expect(networkStorage.position, _position(1, 1));
  });

  test('waits for the complete grace period before GPS fallback', () async {
    final platform = _FakeLocationPlatform(current: _position(2, 2));
    final service = PreferredLocationService(
      platform: platform,
      networkSource: _FakeNetworkSource(),
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );
    final stopwatch = Stopwatch()..start();

    final result = await service.getCurrentPosition();

    expect(result, _position(2, 2));
    expect(stopwatch.elapsed, greaterThanOrEqualTo(grace));
    expect(platform.currentCalls, 1);
  });

  test('does not call Android channel on non-Android platforms', () async {
    final current = _position(2, 2);
    final platform = _FakeLocationPlatform(current: current);
    final network = _FakeNetworkSource(position: _position(1, 1));
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: false,
    );

    final result = await service.getCurrentPosition();

    expect(result, current);
    expect(network.currentCalls, 0);
    expect(platform.lastKnownCalls, 0);
  });

  test('keeps the non-Android cached fallback unchanged', () async {
    final cached = _position(3, 3);
    final platform = _FakeLocationPlatform(
      current: _position(2, 2),
      cached: cached,
      currentError: const PositionUpdateException('unavailable'),
    );
    final network = _FakeNetworkSource(position: _position(1, 1));
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: false,
    );

    expect(await service.getCurrentPosition(), cached);
    expect(network.currentCalls, 0);
    expect(platform.lastKnownCalls, 1);
  });

  test('prefers trusted network cache when fresh sources fail', () async {
    final trustedNetwork = _position(4, 4);
    final platform = _FakeLocationPlatform(
      current: _position(2, 2),
      cached: _position(3, 3),
      currentError: const PositionUpdateException('unavailable'),
    );
    final generalStorage = _FakeLocationStorage(position: _position(5, 5));
    final service = PreferredLocationService(
      platform: platform,
      networkSource: _FakeNetworkSource(),
      storage: generalStorage,
      networkStorage: _FakeLocationStorage(position: trustedNetwork),
      preferAndroidNetwork: true,
      networkFallbackDelay: Duration.zero,
    );

    final result = await service.getCurrentPosition();

    expect(result, trustedNetwork);
    expect(platform.lastKnownCalls, 0);
    expect(generalStorage.readCalls, 0);
  });

  test('falls back to system GPS cache after trusted network cache', () async {
    final systemCached = _position(3, 3);
    final generalStorage = _FakeLocationStorage(position: _position(4, 4));
    final service = PreferredLocationService(
      platform: _FakeLocationPlatform(
        current: _position(2, 2),
        cached: systemCached,
        currentError: const PositionUpdateException('unavailable'),
      ),
      networkSource: _FakeNetworkSource(),
      storage: generalStorage,
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: Duration.zero,
    );

    final result = await service.getCurrentPosition();

    expect(result, systemCached);
    expect(generalStorage.readCalls, 0);
  });

  test('rejects mocked fixes from both Android sources', () async {
    final trustedCached = _position(4, 4);
    final service = PreferredLocationService(
      platform: _FakeLocationPlatform(
        current: _position(2, 2, isMocked: true),
        cached: _position(3, 3, isMocked: true),
      ),
      networkSource: _FakeNetworkSource(
        position: _position(1, 1, isMocked: true),
      ),
      storage: _FakeLocationStorage(position: _position(5, 5, isMocked: true)),
      networkStorage: _FakeLocationStorage(position: trustedCached),
      preferAndroidNetwork: true,
      networkFallbackDelay: Duration.zero,
    );

    expect(await service.getCurrentPosition(), trustedCached);
  });

  test('throws when location permission remains denied', () async {
    final platform = _FakeLocationPlatform(
      current: _position(2, 2),
      permission: LocationPermission.denied,
      requestedPermission: LocationPermission.deniedForever,
    );
    final network = _FakeNetworkSource(position: _position(1, 1));
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
    );

    expect(
      service.getCurrentPosition,
      throwsA(isA<PermissionDeniedException>()),
    );
    expect(network.currentCalls, 0);
  });

  test('brief network gaps never start the GPS stream', () async {
    final network = _FakeNetworkSource();
    final gps = StreamController<Position>.broadcast(sync: true);
    final platform = _FakeLocationPlatform(
      current: _position(9, 9),
      stream: gps.stream,
    );
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );
    final received = <Position>[];
    final subscription = service.watchCurrentPosition().listen(received.add);
    await _flush();

    network.add(_position(1, 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    network.add(_position(1.1, 1.1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    network.add(_position(1.2, 1.2));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(platform.streamCalls, 0);
    expect(received, [
      _position(1, 1),
      _position(1.1, 1.1),
      _position(1.2, 1.2),
    ]);

    await subscription.cancel();
    await gps.close();
    await network.close();
  });

  test('starts GPS only after network has been silent for the grace', () async {
    final network = _FakeNetworkSource();
    final gps = StreamController<Position>.broadcast(sync: true);
    final platform = _FakeLocationPlatform(
      current: _position(9, 9),
      stream: gps.stream,
    );
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );
    final received = <Position>[];
    final subscription = service.watchCurrentPosition().listen(received.add);
    await _flush();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.streamCalls, 0);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(platform.streamCalls, 1);
    gps.add(_position(2, 2));
    await _flush();
    expect(received, [_position(2, 2)]);

    await subscription.cancel();
    await gps.close();
    await network.close();
  });

  test('provider outage must last for the full grace before GPS', () async {
    final network = _FakeNetworkSource();
    final gps = StreamController<Position>.broadcast(sync: true);
    final platform = _FakeLocationPlatform(
      current: _position(9, 9),
      stream: gps.stream,
    );
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );
    final subscription = service.watchCurrentPosition().listen((_) {});
    await _flush();
    network.add(_position(1, 1));
    await _flush();

    network.setProviderAvailable(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.streamCalls, 0);

    network.setProviderAvailable(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(platform.streamCalls, 0);

    network.setProviderAvailable(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(platform.streamCalls, 1);

    await subscription.cancel();
    await gps.close();
    await network.close();
  });

  test('network recovery suppresses further GPS events immediately', () async {
    final network = _FakeNetworkSource();
    final gps = StreamController<Position>.broadcast(sync: true);
    final platform = _FakeLocationPlatform(
      current: _position(9, 9),
      stream: gps.stream,
    );
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );
    final received = <Position>[];
    final subscription = service.watchCurrentPosition().listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    gps.add(_position(2, 2));
    network.add(_position(1, 1));
    gps.add(_position(3, 3));
    await _flush();

    expect(received, [_position(2, 2), _position(1, 1)]);

    await subscription.cancel();
    await gps.close();
    await network.close();
  });

  test('mocked network event cannot postpone the GPS fallback', () async {
    final network = _FakeNetworkSource();
    final gps = StreamController<Position>.broadcast(sync: true);
    final platform = _FakeLocationPlatform(
      current: _position(9, 9),
      stream: gps.stream,
    );
    final service = PreferredLocationService(
      platform: platform,
      networkSource: network,
      storage: _FakeLocationStorage(),
      networkStorage: _FakeLocationStorage(),
      preferAndroidNetwork: true,
      networkFallbackDelay: grace,
    );
    final subscription = service.watchCurrentPosition().listen((_) {});
    await _flush();

    network.add(_position(1, 1, isMocked: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(platform.streamCalls, 1);

    await subscription.cancel();
    await gps.close();
    await network.close();
  });

  test('native channel explicitly owns NETWORK_PROVIDER updates', () {
    final source = File(
      'android/app/src/main/kotlin/com/parktrack/mobile/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('"com.parktrack.mobile/network_location"'));
    expect(
      source,
      contains(
        'manager.requestLocationUpdates(\n'
        '                LocationManager.NETWORK_PROVIDER,',
      ),
    );
    expect(source, contains('manager.removeUpdates(listener)'));
    expect(source, contains('stopNetworkLocationUpdates()'));
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Position _position(
  double latitude,
  double longitude, {
  bool isMocked = false,
}) => Position(
  longitude: longitude,
  latitude: latitude,
  timestamp: DateTime.utc(2026),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: isMocked,
);

class _FakeNetworkSource implements NetworkPositionSource {
  _FakeNetworkSource({this.position});

  final Position? position;
  final StreamController<NetworkPositionUpdate> _controller =
      StreamController<NetworkPositionUpdate>.broadcast(sync: true);
  int currentCalls = 0;
  int watchCalls = 0;

  void add(Position position) {
    _controller.add(
      NetworkPositionUpdate(providerAvailable: true, position: position),
    );
  }

  void setProviderAvailable(bool available) {
    _controller.add(NetworkPositionUpdate(providerAvailable: available));
  }

  Future<void> close() => _controller.close();

  @override
  Future<Position?> getCurrentPosition() async {
    currentCalls++;
    return position;
  }

  @override
  Stream<NetworkPositionUpdate> watchPositions() {
    watchCalls++;
    return _controller.stream;
  }
}

class _FakeLocationPlatform implements LocationPlatformClient {
  _FakeLocationPlatform({
    required this.current,
    this.cached,
    this.currentError,
    this.stream = const Stream<Position>.empty(),
    this.permission = LocationPermission.whileInUse,
    this.requestedPermission = LocationPermission.whileInUse,
  });

  final Position current;
  final Position? cached;
  final Object? currentError;
  final Stream<Position> stream;
  final LocationPermission permission;
  final LocationPermission requestedPermission;

  int lastKnownCalls = 0;
  int currentCalls = 0;
  int streamCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({
    required LocationSettings locationSettings,
  }) async {
    currentCalls++;
    if (currentError case final error?) throw error;
    return current;
  }

  @override
  Stream<Position> getPositionStream({
    required LocationSettings locationSettings,
  }) {
    streamCalls++;
    return stream;
  }

  @override
  Future<Position?> getLastKnownPosition() async {
    lastKnownCalls++;
    return cached;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> requestPermission() async => requestedPermission;
}

class _FakeLocationStorage implements LocationPositionStorage {
  _FakeLocationStorage({this.position});

  Position? position;
  int readCalls = 0;
  int writeCalls = 0;

  @override
  Future<void> clear() async => position = null;

  @override
  Future<Position?> read() async {
    readCalls++;
    return position;
  }

  @override
  Future<void> write(Position position) async {
    writeCalls++;
    this.position = position;
  }
}
