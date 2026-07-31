import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/models/route_result.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/providers/routing_provider.dart';
import 'package:mobile/presentation/screens/map/map_screen.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

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

  test(
    'destination route preview resolves the selected place as its target',
    () {
      const route = ActiveRoute(
        routeId: 0,
        status: 'ready',
        selectedZoneId: destinationRouteZoneId,
        routePolyline: [
          Point(latitude: 61.78, longitude: 34.35),
          Point(latitude: 61.789114, longitude: 34.359757),
        ],
        routeDistanceMeters: 1200,
        routeDurationSeconds: 180,
        candidates: [],
      );

      final target = resolveRoutePreviewTarget(
        route: route,
        zones: const <Zone>[],
        destination: destination,
      );

      expect(target?.latitude, destination.latitude);
      expect(target?.longitude, destination.longitude);
    },
  );
}
