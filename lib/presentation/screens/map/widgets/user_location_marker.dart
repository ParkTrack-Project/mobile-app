import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const double userLocationMarkerLogicalSize = 64;

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
  const center = Offset(32, 32);
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
  const center = Offset(32, 32);
  final path = Path()
    ..moveTo(center.dx, center.dy - 30)
    ..lineTo(center.dx + 17.6, center.dy)
    ..lineTo(center.dx - 17.6, center.dy)
    ..close();

  canvas.drawPath(
    path.shift(const Offset(0, 2)),
    Paint()
      ..color = const Color(0x29000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
  );
  canvas.drawPath(path, Paint()..color = const Color(0xFFD83329));
}

void _drawPoint(Canvas canvas, Offset center) {
  canvas.drawCircle(
    center + const Offset(0, 2),
    18,
    Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3.5),
  );
  canvas.drawCircle(center, 18.5, Paint()..color = const Color(0x08000000));
  canvas.drawCircle(center, 18, Paint()..color = Colors.white);
  canvas.drawCircle(center, 13.5, Paint()..color = const Color(0xFFFF3B30));

  final highlight = Paint()
    ..shader = ui.Gradient.radial(
      center - const Offset(4, 5),
      14,
      const [Color(0x55FFFFFF), Color(0x00FFFFFF)],
      const [0, 1],
    );
  canvas.drawCircle(center, 13.5, highlight);
  canvas.drawCircle(
    center + const Offset(0, 1),
    13.5,
    Paint()
      ..color = const Color(0x24000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}
