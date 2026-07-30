import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const double userLocationMarkerLogicalSize = 128;
const double userLocationPointDiameter = 72;
const double userLocationPointBorderWidth = 6;
const double userLocationPointInset = 9;
const Color userLocationMarkerColor = Color(0xFFFF3B30);
const Color userLocationArrowColor = Color(0xFFD83329);
const Color userLocationAccuracyStrokeColor = Color(0x99FF3B30);
const Color userLocationAccuracyFillColor = Color(0x24FF3B30);
const double userLocationAccuracyStrokeWidth = 2;

class UserLocationMarkerBitmaps {
  const UserLocationMarkerBitmaps({
    required this.pin,
    required this.arrow,
    required this.scale,
  });

  final Uint8List pin;
  final Uint8List arrow;
  final double scale;
}

Future<UserLocationMarkerBitmaps> buildUserLocationMarkerBitmaps({
  required double devicePixelRatio,
}) async {
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  return UserLocationMarkerBitmaps(
    pin: await _buildUserLocationMarkerBitmap(dpr: dpr, includeArrow: false),
    arrow: await _buildUserLocationMarkerBitmap(dpr: dpr, includeArrow: true),
    scale: 1 / dpr,
  );
}

Future<Uint8List> _buildUserLocationMarkerBitmap({
  required double dpr,
  required bool includeArrow,
}) async {
  const size = userLocationMarkerLogicalSize;
  const center = Offset(64, 64);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(dpr);

  if (includeArrow) {
    _drawArrow(canvas);
  }
  _drawPoint(canvas, center);

  final imageSize = (size * dpr).round();
  final picture = recorder.endRecording();
  final image = await picture.toImage(imageSize, imageSize);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void _drawArrow(Canvas canvas) {
  // The source CSS polygon is doubled to 60 × 110. Rotating it by -90°
  // gives MapKit a north-facing bitmap for a zero-degree device heading.
  final path = Path()
    ..moveTo(28.8, 64)
    ..lineTo(64, 4)
    ..lineTo(99.2, 64)
    ..lineTo(64, 64)
    ..close();

  canvas.drawPath(
    path.shift(const Offset(0, 4)),
    Paint()
      ..color = const Color(0x29000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
  );
  canvas.drawPath(path, Paint()..color = userLocationArrowColor);
}

void _drawPoint(Canvas canvas, Offset center) {
  const outerRadius = userLocationPointDiameter / 2;
  const innerWhiteRadius = outerRadius - userLocationPointBorderWidth;
  const redRadius = innerWhiteRadius - userLocationPointInset;

  // The original CSS shadow is doubled with the rest of the marker.
  canvas.drawCircle(
    center + const Offset(0, 4),
    outerRadius,
    Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7),
  );
  canvas.drawCircle(
    center,
    outerRadius + 1,
    Paint()
      ..color = const Color(0x08000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  canvas.drawCircle(
    center,
    outerRadius,
    Paint()..color = const Color(0xEBFFFFFF),
  );
  canvas.drawCircle(center, innerWhiteRadius, Paint()..color = Colors.white);

  canvas.drawCircle(
    center + const Offset(0, 2),
    redRadius,
    Paint()
      ..color = const Color(0x2E000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
  );
  canvas.drawCircle(
    center,
    redRadius,
    Paint()..color = userLocationMarkerColor,
  );

  final highlight = Paint()
    ..shader = ui.Gradient.radial(
      center - const Offset(8, 10),
      redRadius,
      const [Color(0x52FFFFFF), Color(0x00FFFFFF)],
      const [0, 1],
    );
  canvas.drawCircle(center, redRadius, highlight);
}
