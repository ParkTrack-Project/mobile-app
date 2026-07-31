import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/providers/app_providers.dart';
import 'package:mobile/presentation/providers/routing_provider.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

Map<String, dynamic> _routeResponse({required bool withGeometry}) => {
  'route_id': 42,
  'status': 'active',
  'mode': 'find_parking',
  'selected_zone_id': 7,
  'selected_candidate': {
    'zone_id': 7,
    'rank': 1,
    'current_free_count': 3,
    'current_confidence': 0.9,
    'pay': 0,
    'duration_from_origin_seconds': 180,
    if (withGeometry)
      'route_geometry': {
        'type': 'LineString',
        'coordinates': [
          [34.35, 61.78],
          [34.36, 61.79],
        ],
      },
  },
};

ProviderContainer _container({required bool withGeometry}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.parktrack.live/api/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        expect(options.path, '/routing/new');
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: _routeResponse(withGeometry: withGeometry),
          ),
        );
      },
    ),
  );
  return ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
}

void main() {
  test('publishes a local preview for a destination route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const points = [
      Point(latitude: 61.78, longitude: 34.35),
      Point(latitude: 61.79, longitude: 34.36),
    ];

    container.read(routingProvider.notifier).showDestinationRoutePreview((
      points: points,
      distanceMeters: 1200,
      durationSeconds: 180,
    ));

    final route = container
        .read(routingProvider)
        .maybeWhen(routePreview: (value) => value, orElse: () => null);
    expect(route?.selectedZoneId, destinationRouteZoneId);
    expect(route?.routePolyline, points);
    expect(route?.routeDistanceMeters, 1200);
    expect(route?.routeDurationSeconds, 180);
  });

  test('uses backend route geometry before the browser fallback', () async {
    final container = _container(withGeometry: true);
    addTearDown(container.dispose);
    var fallbackCalls = 0;

    await container
        .read(routingProvider.notifier)
        .buildRoute(
          originLat: 61.78,
          originLon: 34.35,
          selectedZoneId: 7,
          routeGeometryFallback: () async {
            fallbackCalls++;
            return (
              points: const [
                Point(latitude: 1, longitude: 1),
                Point(latitude: 2, longitude: 2),
              ],
              distanceMeters: 10,
              durationSeconds: 10,
            );
          },
        );

    expect(fallbackCalls, 0);
    final route = container
        .read(routingProvider)
        .maybeWhen(routePreview: (value) => value, orElse: () => null);
    expect(route?.routePolyline, hasLength(2));
    expect(route?.routePolyline?.first.latitude, 61.78);
  });

  test('uses browser v3 only when backend geometry is absent', () async {
    final container = _container(withGeometry: false);
    addTearDown(container.dispose);
    var fallbackCalls = 0;

    await container
        .read(routingProvider.notifier)
        .buildRoute(
          originLat: 61.78,
          originLon: 34.35,
          selectedZoneId: 7,
          routeGeometryFallback: () async {
            fallbackCalls++;
            return (
              points: const [
                Point(latitude: 61.78, longitude: 34.35),
                Point(latitude: 61.79, longitude: 34.36),
              ],
              distanceMeters: 1200,
              durationSeconds: 180,
            );
          },
        );

    expect(fallbackCalls, 1);
    final route = container
        .read(routingProvider)
        .maybeWhen(routePreview: (value) => value, orElse: () => null);
    expect(route?.routePolyline, hasLength(2));
    expect(route?.routeDistanceMeters, 1200);
    expect(route?.routeDurationSeconds, 180);
  });
}
