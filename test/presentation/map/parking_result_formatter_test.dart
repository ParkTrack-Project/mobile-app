import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/presentation/screens/map/widgets/parking_result_formatter.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  test('formats distance, time, price, and spaces in English', () {
    expect(formatParkingDistance(150, AppStrings.en), '150 m');
    expect(formatParkingDistance(1400, AppStrings.en), '1.4 km');
    expect(formatParkingDuration(181, AppStrings.en), '4 min');
    expect(formatParkingDuration(1727 * 60, AppStrings.en), '28 h 47 min');
    expect(formatParkingDistance(172700, AppStrings.en), '173 km');
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

  test(
    'formats destination walk time, arrival, and real polyline distance',
    () {
      expect(formatParkingWalkingDuration(160, AppStrings.en), '~2 min');
      expect(formatParkingWalkingDuration(4720, AppStrings.en), '~59 min');
      expect(formatParkingWalkingDuration(4800, AppStrings.en), '~1 h');
      expect(formatParkingWalkingDuration(4880, AppStrings.en), '~1 h 1 min');
      expect(formatParkingWalkingDuration(4880, AppStrings.ru), '~1 ч 1 мин');
      expect(formatParkingArrival('2026-07-23T13:23:00+03:00'), '13:23');
      expect(
        formatParkingArrivalEstimate(
          null,
          360,
          now: DateTime(2026, 7, 23, 11, 55),
        ),
        '12:01',
      );
      final distance = parkingPolylineLengthMeters(const [
        Point(latitude: 61.789, longitude: 34.359),
        Point(latitude: 61.790, longitude: 34.359),
      ]);
      expect(distance, inInclusiveRange(110, 112));
    },
  );
}
