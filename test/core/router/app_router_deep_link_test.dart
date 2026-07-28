import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router/app_router.dart';

void main() {
  test('creates a destination from valid deep-link coordinates', () {
    final destination = destinationFromDeepLink(
      Uri.parse('/destination?lat=61.789114&lon=34.359757&name=Station'),
    );

    expect(destination?.latitude, 61.789114);
    expect(destination?.longitude, 34.359757);
    expect(destination?.name, 'Station');
  });

  test('rejects invalid destination coordinates', () {
    expect(
      destinationFromDeepLink(Uri.parse('/destination?lat=100&lon=34.359757')),
      isNull,
    );
  });
}
