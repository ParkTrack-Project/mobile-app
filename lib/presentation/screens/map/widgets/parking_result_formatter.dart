import '../../../../core/localization/app_localizations.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'dart:math' as math;

String? formatParkingDistance(int? meters, AppStrings strings) {
  if (meters == null || meters < 0) return null;
  if (meters < 1000) return '$meters ${strings.metersSign}';
  final value = (meters / 1000).toStringAsFixed(1);
  final localizedValue = strings.kmSign == 'км'
      ? value.replaceAll('.', ',')
      : value;
  return '$localizedValue ${strings.kmSign}';
}

String? formatParkingDuration(int? seconds, AppStrings strings) {
  if (seconds == null || seconds <= 0) return null;
  final minutes = (seconds / 60).ceil();
  return '$minutes ${strings.minutesSign}';
}

String? formatParkingSpaces(int? count, AppStrings strings) {
  if (count == null || count < 0) return null;
  final label = strings.metersSign == 'м'
      ? switch (count % 100) {
          >= 11 && <= 14 => strings.parkingSpaceMany,
          _ => switch (count % 10) {
            1 => strings.parkingSpaceOne,
            >= 2 && <= 4 => strings.parkingSpaceFew,
            _ => strings.parkingSpaceMany,
          },
        }
      : count == 1
      ? strings.parkingSpaceOne
      : strings.parkingSpaceMany;
  return '$count $label';
}

String? formatParkingPrice(int? pricePerHour, AppStrings strings) {
  if (pricePerHour == null || pricePerHour < 0) return null;
  if (pricePerHour == 0) return strings.freeStatus;
  return '$pricePerHour ₽/${strings.hourSign}';
}

String? formatParkingWalkingDuration(int? meters, AppStrings strings) {
  if (meters == null || meters < 0) return null;
  final minutes = math.max(1, (meters / 80).ceil());
  return '~$minutes ${strings.minutesSign}';
}

String? formatParkingArrival(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed != null) {
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
  return match == null
      ? null
      : '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
}

String? formatParkingArrivalEstimate(
  String? value,
  int? durationSeconds, {
  DateTime? now,
}) {
  final apiValue = formatParkingArrival(value);
  if (apiValue != null) return apiValue;
  if (durationSeconds == null || durationSeconds <= 0) return null;
  final arrival = (now ?? DateTime.now()).add(
    Duration(seconds: durationSeconds),
  );
  final hour = arrival.hour.toString().padLeft(2, '0');
  final minute = arrival.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

int? parkingPolylineLengthMeters(List<Point>? points) {
  if (points == null || points.length < 2) return null;
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    total += _haversineMeters(points[index - 1], points[index]);
  }
  return total.isFinite ? total.round() : null;
}

double _haversineMeters(Point from, Point to) {
  const earthRadius = 6371000.0;
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLat = (to.latitude - from.latitude) * math.pi / 180;
  final dLon = (to.longitude - from.longitude) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
