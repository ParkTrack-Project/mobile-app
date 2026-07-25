import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/parking_address_native.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  group('formatAndroidParkingAddress', () {
    test('puts street and house before locality', () {
      expect(
        formatAndroidParkingAddress(
          components: const {
            SearchComponentKind.locality: 'Петрозаводск',
            SearchComponentKind.street: 'проспект Ленина',
            SearchComponentKind.house: '10',
          },
          formattedAddress: 'Россия, Петрозаводск, проспект Ленина, 10',
        ),
        'проспект Ленина, 10, Петрозаводск',
      );
    });

    test('omits missing and duplicate components', () {
      expect(
        formatAndroidParkingAddress(
          components: const {
            SearchComponentKind.street: 'Петрозаводск',
            SearchComponentKind.locality: 'Петрозаводск',
          },
          formattedAddress: 'Петрозаводск',
        ),
        'Петрозаводск',
      );

      expect(
        formatAndroidParkingAddress(
          components: const {
            SearchComponentKind.house: '12',
            SearchComponentKind.locality: 'Петрозаводск',
          },
          formattedAddress: '',
        ),
        '12, Петрозаводск',
      );
    });

    test('falls back to normalized formatted address', () {
      expect(
        formatAndroidParkingAddress(
          components: const {},
          formattedAddress: '  Россия, Карелия  ',
        ),
        'Россия, Карелия',
      );

      expect(
        formatAndroidParkingAddress(
          components: const {},
          formattedAddress: '   ',
        ),
        isNull,
      );
    });
  });
}
