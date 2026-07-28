import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/providers/routing_provider.dart';
import 'package:mobile/presentation/screens/map/map_screen.dart';

void main() {
  const destination = Destination(
    latitude: 61.789114,
    longitude: 34.359757,
    name: 'Петрозаводск',
  );

  test('selected destination dismisses standalone parking details', () {
    expect(
      shouldDismissParkingDetailsForDestination(
        destination: destination,
        hasStandaloneParkingDetails: true,
      ),
      isTrue,
    );
    expect(
      shouldDismissParkingDetailsForDestination(
        destination: destination,
        hasStandaloneParkingDetails: false,
      ),
      isFalse,
    );
    expect(
      shouldDismissParkingDetailsForDestination(
        destination: null,
        hasStandaloneParkingDetails: true,
      ),
      isFalse,
    );
  });
}
