import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/presentation/screens/map/map_screen.dart';
import 'package:mobile/presentation/screens/map/widgets/user_location_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds DPR-aware marker images', () async {
    final marker = await buildUserLocationMarkerBitmaps(devicePixelRatio: 2);
    final image = await _decode(marker.pin);

    expect(image.width, 256);
    expect(image.height, 256);
    expect(marker.scale, 0.5);
  });

  test('pin bitmap matches the doubled white and red circles', () async {
    final marker = await buildUserLocationMarkerBitmaps(devicePixelRatio: 1);
    final image = await _decode(marker.pin);
    final pixels = await _pixels(image);

    expect(_pixel(pixels, image.width, 64, 64), _isCloseToColor(0xFFFF3B30));
    expect(_pixel(pixels, image.width, 82, 64), _isCloseToColor(0xFFFF3B30));
    expect(_pixel(pixels, image.width, 88, 64), _isCloseToColor(0xFFFFFFFF));
    expect(_pixel(pixels, image.width, 90, 64), _isCloseToColor(0xFFFFFFFF));
    expect(_pixel(pixels, image.width, 98, 64), _isCloseToColor(0xFFFFFFFF));
    expect(_alpha(_pixel(pixels, image.width, 0, 0)), 0);
  });

  test('arrow bitmap adds direction arrow above the circle', () async {
    final marker = await buildUserLocationMarkerBitmaps(devicePixelRatio: 1);
    final pin = await _decode(marker.pin);
    final arrow = await _decode(marker.arrow);
    final pinPixels = await _pixels(pin);
    final arrowPixels = await _pixels(arrow);

    expect(_alpha(_pixel(pinPixels, pin.width, 64, 16)), lessThanOrEqualTo(2));
    expect(
      _pixel(arrowPixels, arrow.width, 64, 16),
      _isCloseToColor(0xFFD83329),
    );
    expect(_alpha(_pixel(arrowPixels, arrow.width, 64, 4)), greaterThan(20));
    expect(
      _pixel(arrowPixels, arrow.width, 64, 100),
      isNot(_isCloseToColor(0xFFD83329)),
    );
  });

  test('Android renders a managed rotating marker and accuracy circle', () {
    final source = File(
      'lib/presentation/screens/map/map_screen.dart',
    ).readAsStringSync();

    expect(source, contains("MapObjectId('android_user_location_marker')"));
    expect(source, contains("MapObjectId('android_user_location_accuracy')"));
    expect(source, contains('_userLocationMarkerBitmaps!.arrow'));
    expect(source, contains('rotationType: RotationType.rotate'));
    expect(source, contains('direction: managedAndroidHeading'));
    expect(source, contains('userLocationAccuracyFillColor'));
    expect(source, contains('userLocationAccuracyStrokeColor'));
    expect(source, contains('userLocationMarkerOpacity'));
    expect(source, contains('shouldShowUserLocationAccuracyCircle('));
  });

  test('Android managed marker is hidden during navigation', () {
    final source = File(
      'lib/presentation/screens/map/map_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'final managedAndroidPosition =\n'
        '          _usesManagedAndroidLocation && !isNavigating '
        '? _userPosition : null;',
      ),
    );
    expect(
      source,
      contains('final managedAndroidPoint = managedAndroidPosition == null'),
    );
    expect(source, contains('_displayedUserPoint ??'));
    expect(source, contains("MapObjectId('nav_arrow')"));
  });

  test('Android managed marker uses animated displayed user point', () {
    final source = File(
      'lib/presentation/screens/map/map_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('with WidgetsBindingObserver, TickerProviderStateMixin'),
    );
    expect(source, isNot(contains('SingleTickerProviderStateMixin')));
    expect(source, contains('_animateDisplayedUserPoint(point)'));
    expect(source, contains('_tickDisplayedUserPoint'));
    expect(source, contains('interpolateMapPoint(start, end, eased)'));
    expect(source, contains('_syncFollowingCamera(target: point'));
  });

  test(
    'location camera mode survives programmatic camera and location updates',
    () {
      final source = File(
        'lib/presentation/screens/map/map_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          'locationCameraModeAfterMapCameraUpdate(\n'
          '      mode: _myLocationCameraMode,\n'
          '      userGesture: reason == CameraUpdateReason.gestures,',
        ),
      );
      expect(
        source,
        contains(
          'locationCameraModeAfterMapCameraUpdate(\n'
          '      mode: _myLocationCameraMode,\n'
          '      userGesture: camera.userGesture,',
        ),
      );
      expect(source, isNot(contains('_isCameraCenteredOnUser')));
      expect(source, contains('_syncFollowingCamera(target: point'));
      expect(source, contains('durationSeconds: 0'));
    },
  );

  test('following mode keeps zoom buttons and marker heading in sync', () {
    final source = File(
      'lib/presentation/screens/map/map_screen.dart',
    ).readAsStringSync();
    final changeZoomStart = source.indexOf('Future<void> _changeZoom(');
    final zoomInStart = source.indexOf(
      'Future<void> _zoomIn()',
      changeZoomStart,
    );
    final changeZoomSource = source.substring(changeZoomStart, zoomInStart);
    final headingTrackingStart = source.indexOf(
      'Future<void> _startAndroidHeadingTracking',
    );
    final applyPositionStart = source.indexOf(
      'void _applyUserPosition',
      headingTrackingStart,
    );
    final headingTrackingSource = source.substring(
      headingTrackingStart,
      applyPositionStart,
    );

    expect(changeZoomSource, isNot(contains('_resetMyLocationCameraMode()')));
    expect(
      changeZoomSource,
      contains('_myLocationCameraMode == MyLocationCameraMode.following'),
    );
    expect(changeZoomSource, contains('await _syncFollowingCamera('));
    expect(
      source,
      contains('_myLocationCameraMode == MyLocationCameraMode.following'),
    );
    expect(
      headingTrackingSource,
      contains('? heading\n          : smoothCircularHeading'),
    );
    expect(headingTrackingSource, contains('_scheduleFollowingCamera();'));
  });

  test(
    'Android tracking uses one arbitrated stream without periodic races',
    () {
      final source = File(
        'lib/presentation/screens/map/map_screen.dart',
      ).readAsStringSync();

      expect(source, contains('service.watchCurrentPosition().listen'));
      expect(
        source,
        isNot(contains('Timer.periodic(_androidLocationRefreshInterval')),
      );
      expect(source, isNot(contains('_startAndroidLocationRefreshTimer')));
      expect(source, contains('onDone: ()'));
      expect(source, contains('_scheduleAndroidLocationRetry(generation)'));
      expect(source, contains('generation != _locationTrackingGeneration'));
    },
  );

  test('waits for bitmaps before starting managed Android tracking', () {
    final source = File(
      'lib/presentation/screens/map/map_screen.dart',
    ).readAsStringSync();
    final callbackStart = source.indexOf('onMapCreated: (controller) async');
    final trackingStart = source.indexOf(
      '_startAndroidLocationTracking()',
      callbackStart,
    );
    final beforeTracking = source.substring(callbackStart, trackingStart);

    expect(beforeTracking, contains('await (_markerBitmapsFuture ??'));
    expect(beforeTracking, contains('_syncNativeUserLayer(visible: false)'));
  });

  test('stale location marker is translucent', () {
    expect(userLocationMarkerOpacity(UserLocationFreshness.current), 1);
    expect(userLocationMarkerOpacity(UserLocationFreshness.stale), 0.6);
  });

  test('accuracy circle is shown only for low current accuracy', () {
    expect(
      shouldShowUserLocationAccuracyCircle(
        accuracy: 5,
        freshness: UserLocationFreshness.current,
      ),
      isFalse,
    );
    expect(
      shouldShowUserLocationAccuracyCircle(
        accuracy: userLocationAccuracyCircleThresholdMeters,
        freshness: UserLocationFreshness.current,
      ),
      isFalse,
    );
    expect(
      shouldShowUserLocationAccuracyCircle(
        accuracy: 21,
        freshness: UserLocationFreshness.current,
      ),
      isTrue,
    );
    expect(
      shouldShowUserLocationAccuracyCircle(
        accuracy: 100,
        freshness: UserLocationFreshness.stale,
      ),
      isFalse,
    );
    expect(
      shouldShowUserLocationAccuracyCircle(
        accuracy: double.nan,
        freshness: UserLocationFreshness.current,
      ),
      isFalse,
    );
  });

  test('location becomes stale after the freshness interval', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    expect(isUserPositionFresh(_position(now), now), isTrue);
    expect(
      isUserPositionFresh(
        _position(now.subtract(const Duration(seconds: 21))),
        now,
      ),
      isFalse,
    );
  });

  test('accuracy fill is red and more transparent than its stroke', () {
    expect(_red(userLocationAccuracyFillColor), 255);
    expect(_green(userLocationAccuracyFillColor), 59);
    expect(_blue(userLocationAccuracyFillColor), 48);
    expect(
      _alpha(userLocationAccuracyFillColor),
      lessThan(_alpha(userLocationAccuracyStrokeColor)),
    );
    expect(userLocationAccuracyStrokeWidth, 2);
  });
}

Future<ui.Image> _decode(Uint8List bytes) {
  return ui.instantiateImageCodec(bytes).then((codec) async {
    final frame = await codec.getNextFrame();
    return frame.image;
  });
}

Future<ByteData> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!;
}

Color _pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

Matcher _isCloseToColor(int value) {
  final expected = Color(value);
  return predicate<Color>((actual) {
    return (_red(actual) - _red(expected)).abs() <= 40 &&
        (_green(actual) - _green(expected)).abs() <= 40 &&
        (_blue(actual) - _blue(expected)).abs() <= 40 &&
        _alpha(actual) >= 220;
  }, 'is close to ${expected.toARGB32().toRadixString(16)}');
}

int _alpha(Color color) => (color.toARGB32() >> 24) & 0xFF;
int _red(Color color) => (color.toARGB32() >> 16) & 0xFF;
int _green(Color color) => (color.toARGB32() >> 8) & 0xFF;
int _blue(Color color) => color.toARGB32() & 0xFF;

Position _position(DateTime timestamp) => Position(
  longitude: 33,
  latitude: 61,
  timestamp: timestamp,
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
