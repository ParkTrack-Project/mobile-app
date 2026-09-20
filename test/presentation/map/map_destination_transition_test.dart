import 'dart:io';

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

  test('reapplies a deep-link destination when each map becomes ready', () {
    final source = File(
      'lib/presentation/screens/map/map_screen.dart',
    ).readAsStringSync();

    final webReady = source.substring(
      source.indexOf('onMapReady: ()'),
      source.indexOf('onMapCreated: (controller) async'),
    );
    final nativeReady = source.substring(
      source.indexOf('onMapCreated: (controller) async'),
      source.indexOf('onCameraPositionChanged:'),
    );

    expect(webReady, contains('ref.read(destinationProvider)'));
    expect(webReady, contains('_focusDestination(readyDestination'));
    expect(nativeReady, contains('ref.read(destinationProvider)'));
    expect(nativeReady, contains('target: initialTarget'));
  });
}
