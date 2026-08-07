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
import 'package:mobile/presentation/providers/time_selector_provider.dart';

class _FakeZonesRepository extends ZonesRepository {
  _FakeZonesRepository()
    : super(ZonesApi(Dio()), OccupancyApi(Dio()), ForecastsApi(Dio()));

  bool fail = false;
  final requestedModes = <String>[];
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
    requestedModes.add('now');
    if (fail) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/zones'),
        reason: 'offline',
      );
    }
    return [cachedZone];
  }

  @override
  Future<List<Zone>> getZonesPast(
    String bbox,
    DateTime at, {
    CancelToken? cancelToken,
  }) async {
    requestedModes.add('past');
    return [cachedZone.copyWith(freeCount: 1)];
  }

  @override
  Future<List<Zone>> getZonesFuture(
    String bbox,
    DateTime at, {
    CancelToken? cancelToken,
  }) async {
    requestedModes.add('future');
    return [cachedZone.copyWith(freeCount: 8)];
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

  test('loads selected-time availability for the same viewport', () async {
    final repository = _FakeZonesRepository();
    final container = ProviderContainer(
      overrides: [zonesRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(rawZonesProvider.notifier);

    await notifier.fetchZones('1,2,3,4');
    expect(container.read(rawZonesProvider).requireValue.single.freeCount, 3);

    container
        .read(timeSelectorProvider.notifier)
        .setPast(DateTime(2026, 8, 7, 10));
    await notifier.fetchZones('1,2,3,4');
    expect(container.read(rawZonesProvider).requireValue.single.freeCount, 1);

    container
        .read(timeSelectorProvider.notifier)
        .setFuture(DateTime(2026, 8, 9, 10));
    await notifier.fetchZones('1,2,3,4');
    expect(container.read(rawZonesProvider).requireValue.single.freeCount, 8);
    expect(repository.requestedModes, ['now', 'past', 'future']);
  });
}
