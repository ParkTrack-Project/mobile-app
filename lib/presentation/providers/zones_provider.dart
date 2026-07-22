import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/zone.dart';
import 'app_providers.dart';
import 'time_selector_provider.dart';
import 'filters_provider.dart';

final rawZonesProvider =
    StateNotifierProvider<ZonesNotifier, AsyncValue<List<Zone>>>(
      (ref) => ZonesNotifier(ref),
    );

class ZonesNotifier extends StateNotifier<AsyncValue<List<Zone>>> {
  ZonesNotifier(this._ref) : super(const AsyncValue.data([]));

  final Ref _ref;
  String? _lastBbox;
  String? _lastRequestKey;
  CancelToken? _cancelToken;
  int _requestGeneration = 0;

  Future<void> fetchZones(String bbox, {bool force = false}) async {
    final timeMode = _ref.read(timeSelectorProvider);
    final requestKey = '$bbox|$timeMode';
    if (!force && requestKey == _lastRequestKey && state.hasValue) return;

    _lastBbox = bbox;
    _lastRequestKey = requestKey;
    final generation = ++_requestGeneration;
    _cancelToken?.cancel('Superseded by a newer viewport request');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    state = const AsyncValue<List<Zone>>.loading().copyWithPrevious(state);
    try {
      final repo = _ref.read(zonesRepositoryProvider);
      final zones = await timeMode.when(
        now: () => repo.getZonesNow(bbox, cancelToken: cancelToken),
        past: (at) => repo.getZonesPast(bbox, at, cancelToken: cancelToken),
        future: (at) => repo.getZonesFuture(bbox, at, cancelToken: cancelToken),
      );
      if (generation != _requestGeneration || cancelToken.isCancelled) return;
      state = AsyncValue.data(zones);
    } on DioException catch (e, st) {
      if (CancelToken.isCancel(e) || generation != _requestGeneration) return;
      state = AsyncValue<List<Zone>>.error(e, st).copyWithPrevious(state);
    } catch (e, st) {
      if (generation != _requestGeneration) return;
      state = AsyncValue<List<Zone>>.error(e, st).copyWithPrevious(state);
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  Future<void> refresh() async {
    if (_lastBbox != null) await fetchZones(_lastBbox!, force: true);
  }

  void clearZones() {
    _requestGeneration++;
    _cancelToken?.cancel('Zone state cleared');
    _cancelToken = null;
    _lastRequestKey = null;
    state = const AsyncValue<List<Zone>>.loading().copyWithPrevious(state);
  }

  void setErrorState(Object error, StackTrace stackTrace) {
    state = AsyncValue<List<Zone>>.error(
      error,
      stackTrace,
    ).copyWithPrevious(state);
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Zones provider disposed');
    super.dispose();
  }
}

final filteredZonesProvider = Provider<List<Zone>>((ref) {
  final zonesAsync = ref.watch(rawZonesProvider);
  final filters = ref.watch(filtersProvider);

  final zones = zonesAsync.valueOrNull ?? [];
  return zones.where((z) {
    if (filters.hideInactive && !z.isActive) return false;
    if (filters.hideNoFreeSpots && z.freeCount == 0) return false;
    if (filters.minFreeCount > 0 && z.freeCount < filters.minFreeCount) {
      return false;
    }
    if (z.confidence < filters.minConfidence) return false;
    if (filters.maxPayPerHour != null && z.pay > filters.maxPayPerHour!) {
      return false;
    }
    if (filters.hidePrivate && (z.isPrivate ?? false)) return false;
    if (filters.hideInaccessible && (z.isAccessible == false)) return false;
    if (z.locationType != null) {
      final typeKey = _locationTypeKey(z.locationType!);
      if (filters.hiddenLocationTypes.contains(typeKey)) return false;
    }
    return true;
  }).toList();
});

String _locationTypeKey(LocationType type) => switch (type) {
  LocationType.street => 'street',
  LocationType.yard => 'yard',
  LocationType.openLot => 'open_lot',
  LocationType.underground => 'underground',
  LocationType.multilevel => 'multilevel',
};
