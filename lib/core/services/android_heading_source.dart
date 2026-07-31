import 'package:flutter/services.dart';

abstract interface class HeadingSource {
  Stream<double> get headings;
}

class AndroidHeadingSource implements HeadingSource {
  const AndroidHeadingSource();

  static const _channel = EventChannel('com.parktrack.mobile/heading');

  @override
  Stream<double> get headings => _channel
      .receiveBroadcastStream()
      .where((value) => value is num)
      .map((value) => (value as num).toDouble())
      .where((value) => value.isFinite)
      .map((value) => ((value % 360) + 360) % 360);
}

double smoothCircularHeading(
  double next,
  double? previous, {
  double alpha = 0.25,
}) {
  final normalizedNext = ((next % 360) + 360) % 360;
  if (previous == null || !previous.isFinite) return normalizedNext;
  final difference = ((normalizedNext - previous + 540) % 360) - 180;
  return (previous + alpha * difference + 360) % 360;
}
