import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

abstract interface class LocationPositionStorage {
  Future<void> write(Position position);

  Future<Position?> read();

  Future<void> clear();
}

class LocationStorage implements LocationPositionStorage {
  LocationStorage({
    FlutterSecureStorage? storage,
    String key = lastSuccessfulLocationKey,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _key = key;

  static const lastSuccessfulLocationKey = 'last_successful_location';
  static const lastSuccessfulNetworkLocationKey =
      'last_successful_network_location';

  final FlutterSecureStorage _storage;
  final String _key;

  @override
  Future<void> write(Position position) async {
    if (!_isValid(position.latitude, position.longitude)) return;
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': position.timestamp.millisecondsSinceEpoch,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'altitudeAccuracy': position.altitudeAccuracy,
        'heading': position.heading,
        'headingAccuracy': position.headingAccuracy,
        'speed': position.speed,
        'speedAccuracy': position.speedAccuracy,
        'isMocked': position.isMocked,
      }),
    );
  }

  @override
  Future<Position?> read() async {
    try {
      final value = await _storage.read(key: _key);
      if (value == null) return null;
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic>) return null;
      final latitude = (data['latitude'] as num?)?.toDouble();
      final longitude = (data['longitude'] as num?)?.toDouble();
      if (latitude == null ||
          longitude == null ||
          !_isValid(latitude, longitude)) {
        return null;
      }
      return Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (data['timestamp'] as num?)?.toInt() ?? 0,
          isUtc: true,
        ),
        accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0,
        altitude: (data['altitude'] as num?)?.toDouble() ?? 0,
        altitudeAccuracy: (data['altitudeAccuracy'] as num?)?.toDouble() ?? 0,
        heading: (data['heading'] as num?)?.toDouble() ?? 0,
        headingAccuracy: (data['headingAccuracy'] as num?)?.toDouble() ?? 0,
        speed: (data['speed'] as num?)?.toDouble() ?? 0,
        speedAccuracy: (data['speedAccuracy'] as num?)?.toDouble() ?? 0,
        isMocked: data['isMocked'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);

  bool _isValid(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}
