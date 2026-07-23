import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/api/forecasts_api.dart';
import 'package:mobile/data/api/occupancy_api.dart';
import 'package:mobile/data/api/zones_api.dart';
import 'package:mobile/data/repositories/zones_repository.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/providers/app_providers.dart';
import 'package:mobile/presentation/providers/zones_provider.dart';

class _FakeZonesRepository extends ZonesRepository {
  _FakeZonesRepository()
    : super(ZonesApi(Dio()), OccupancyApi(Dio()), ForecastsApi(Dio()));

  bool fail = false;
  final cachedZone = const Zone(
    zoneId: 7,
    zoneType: ZoneType.standard,
    capacity: 10,
    freeCount: 3,
    confidence: 0.8,
    pay: 0,
    geometry: [],
  );

  @override
  Future<List<Zone>> getZonesNow(
    String bbox, {
    CancelToken? cancelToken,
  }) async {
    if (fail) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/zones'),
        reason: 'offline',
      );
    }
    return [cachedZone];
  }
}

void main() {
  test('refreshes parking availability inside the requested interval', () {
    expect(
      zoneAutoRefreshInterval,
      greaterThanOrEqualTo(const Duration(seconds: 15)),
    );
    expect(
      zoneAutoRefreshInterval,
      lessThanOrEqualTo(const Duration(seconds: 30)),
    );
  });

  test('keeps cached zones when background refresh fails', () async {
    final repository = _FakeZonesRepository();
    final container = ProviderContainer(
      overrides: [zonesRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(rawZonesProvider.notifier);
    await notifier.fetchZones('1,2,3,4');
    expect(container.read(rawZonesProvider).valueOrNull, [
      repository.cachedZone,
    ]);

    repository.fail = true;
    await notifier.fetchZones('1,2,3,4', force: true);

    final state = container.read(rawZonesProvider);
    expect(state.hasError, isTrue);
    expect(state.hasValue, isTrue);
    expect(state.valueOrNull, [repository.cachedZone]);
  });
}
