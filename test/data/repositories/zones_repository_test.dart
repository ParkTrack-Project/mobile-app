import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/mock_interceptor.dart';
import 'package:mobile/data/api/forecasts_api.dart';
import 'package:mobile/data/api/occupancy_api.dart';
import 'package:mobile/data/api/zones_api.dart';
import 'package:mobile/data/repositories/zones_repository.dart';
import 'package:mobile/domain/models/zone.dart';

void main() {
  late ZonesRepository repository;
  late List<RequestOptions> requests;

  setUp(() {
    requests = [];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.next(options);
          },
        ),
      )
      ..interceptors.add(MockInterceptor());
    repository = ZonesRepository(
      ZonesApi(dio),
      OccupancyApi(dio),
      ForecastsApi(dio),
    );
  });

  test('maps historical free counts for the requested time', () async {
    final zones = await repository.getZonesPast(
      '30,59,31,60',
      DateTime.utc(2026, 8, 7, 10),
    );

    expect(zones.singleWhere((zone) => zone.zoneId == 101).freeCount, 3);
    expect(zones.singleWhere((zone) => zone.zoneId == 101).hasForecast, isTrue);
  });

  test('maps forecasts and marks missing selected-time data', () async {
    final zones = await repository.getZonesFuture(
      '30,59,31,60',
      DateTime.utc(2026, 8, 9, 10),
    );

    expect(zones.singleWhere((zone) => zone.zoneId == 101).freeCount, 4);
    final missing = zones.singleWhere((zone) => zone.zoneId == 102);
    expect(missing.hasForecast, isFalse);
    expect(missing.selectedTimeFreeCount, isNull);
  });

  test('propagates the optional active filter to every map request', () async {
    await repository.getZonesPast(
      '30,59,31,60',
      DateTime.utc(2026, 8, 7, 10),
      isActive: true,
    );

    expect(requests.map((request) => request.uri.path).toSet(), {
      '/zones',
      '/occupancy',
    });
    expect(
      requests.every(
        (request) => request.uri.queryParameters['is_active'] == 'true',
      ),
      isTrue,
    );

    requests.clear();
    await repository.getZonesFuture(
      '30,59,31,60',
      DateTime.utc(2026, 8, 9, 10),
    );
    expect(
      requests.every(
        (request) => !request.uri.queryParameters.containsKey('is_active'),
      ),
      isTrue,
    );
  });
}
