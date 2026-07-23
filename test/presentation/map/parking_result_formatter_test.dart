import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/presentation/screens/map/widgets/parking_result_formatter.dart';

void main() {
  test('formats distance, time, price, and spaces in English', () {
    expect(formatParkingDistance(150, AppStrings.en), '150 m');
    expect(formatParkingDistance(1400, AppStrings.en), '1.4 km');
    expect(formatParkingDuration(181, AppStrings.en), '4 min');
    expect(formatParkingSpaces(1, AppStrings.en), '1 space');
    expect(formatParkingSpaces(12, AppStrings.en), '12 spaces');
    expect(formatParkingPrice(60, AppStrings.en), '60 ₽/h');
    expect(formatParkingPrice(0, AppStrings.en), 'Free');
  });

  test('uses Russian number forms and decimal separator', () {
    expect(formatParkingDistance(1400, AppStrings.ru), '1,4 км');
    expect(formatParkingSpaces(1, AppStrings.ru), '1 место');
    expect(formatParkingSpaces(2, AppStrings.ru), '2 места');
    expect(formatParkingSpaces(12, AppStrings.ru), '12 мест');
    expect(formatParkingSpaces(21, AppStrings.ru), '21 место');
    expect(formatParkingPrice(60, AppStrings.ru), '60 ₽/ч');
  });

  test('omits unavailable and invalid values', () {
    expect(formatParkingDistance(null, AppStrings.en), isNull);
    expect(formatParkingDistance(-1, AppStrings.en), isNull);
    expect(formatParkingDuration(0, AppStrings.en), isNull);
    expect(formatParkingSpaces(-1, AppStrings.en), isNull);
    expect(formatParkingPrice(-1, AppStrings.en), isNull);
  });
}
