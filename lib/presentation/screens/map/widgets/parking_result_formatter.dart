import '../../../../core/localization/app_localizations.dart';

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
