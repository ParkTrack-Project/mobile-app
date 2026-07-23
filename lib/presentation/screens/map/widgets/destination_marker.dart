import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

const destinationMarkerAnchor = Offset(0.5, 1);
const destinationMarkerSize = Size(64, 80);

Future<Uint8List> buildDestinationPinBitmap() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final shadowPath = _pinPath(destinationMarkerSize);

  canvas.drawShadow(shadowPath, Colors.black, 4, true);
  canvas.drawPath(shadowPath, Paint()..color = AppColors.primary);
  canvas.drawPath(
    shadowPath,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  canvas.drawCircle(const Offset(32, 27), 8, Paint()..color = Colors.white);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    destinationMarkerSize.width.toInt(),
    destinationMarkerSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Path _pinPath(Size size) {
  final centerX = size.width / 2;
  return Path()
    ..moveTo(centerX, size.height - 2)
    ..cubicTo(27, 67, 10, 49, 10, 28)
    ..cubicTo(10, 14, 20, 4, centerX, 4)
    ..cubicTo(44, 4, 54, 14, 54, 28)
    ..cubicTo(54, 49, 37, 67, centerX, size.height - 2)
    ..close();
}
