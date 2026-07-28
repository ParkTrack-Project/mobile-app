import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/user_location_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds DPR-aware marker images', () async {
    final marker = await buildUserLocationMarkerBitmaps(devicePixelRatio: 2);
    final image = await _decode(marker.pin);

    expect(image.width, 128);
    expect(image.height, 128);
    expect(marker.scale, 0.5);
  });

  test('pin bitmap keeps Yandex-like circle geometry', () async {
    final marker = await buildUserLocationMarkerBitmaps(devicePixelRatio: 1);
    final image = await _decode(marker.pin);
    final pixels = await _pixels(image);

    expect(_pixel(pixels, image.width, 32, 32), _isCloseToColor(0xFFFF3B30));
    expect(_pixel(pixels, image.width, 47, 32), _isCloseToColor(0xFFFFFFFF));
    expect(_alpha(_pixel(pixels, image.width, 0, 0)), 0);
  });

  test('arrow bitmap adds direction arrow above the circle', () async {
    final marker = await buildUserLocationMarkerBitmaps(devicePixelRatio: 1);
    final pin = await _decode(marker.pin);
    final arrow = await _decode(marker.arrow);
    final pinPixels = await _pixels(pin);
    final arrowPixels = await _pixels(arrow);

    expect(_alpha(_pixel(pinPixels, pin.width, 32, 8)), lessThanOrEqualTo(2));
    expect(
      _pixel(arrowPixels, arrow.width, 32, 8),
      _isCloseToColor(0xFFD83329),
    );
    expect(_alpha(_pixel(arrowPixels, arrow.width, 32, 2)), greaterThan(20));
    expect(
      _pixel(arrowPixels, arrow.width, 32, 50),
      isNot(_isCloseToColor(0xFFD83329)),
    );
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
