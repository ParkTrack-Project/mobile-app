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

  Future<void> fetchZones(String bbox) async {
    _lastBbox = bbox;
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(zonesRepositoryProvider);
      final timeMode = _ref.read(timeSelectorProvider);
      final zones = await timeMode.when(
        now: () => repo.getZonesNow(bbox),
        past: (at) => repo.getZonesPast(bbox, at),
        future: (at) => repo.getZonesFuture(bbox, at),
      );
      state = AsyncValue.data(zones);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    if (_lastBbox != null) await fetchZones(_lastBbox!);
  }

  void setErrorState(Object error, StackTrace stackTrace) {
    state = AsyncValue.error(error, stackTrace);
  }
}

final filteredZonesProvider = Provider<List<Zone>>((ref) {
  final zonesAsync = ref.watch(rawZonesProvider);
  final filters = ref.watch(filtersProvider);

  return zonesAsync.maybeWhen(
    data: (zones) => zones.where((z) {
      if (filters.hideInactive && !z.isActive) return false;
      if (filters.hideNoFreeSpots && z.freeCount == 0) return false;
      if (z.confidence < filters.minConfidence) return false;
      if (filters.maxPayPerHour != null && z.pay > filters.maxPayPerHour!) return false;
      if (filters.hidePrivate && (z.isPrivate ?? false)) return false;
      if (filters.hideInaccessible && (z.isAccessible == false)) return false;
      if (z.locationType != null) {
        final typeKey = _locationTypeKey(z.locationType!);
        if (filters.hiddenLocationTypes.contains(typeKey)) return false;
      }
      return true;
    }).toList(),
    orElse: () => [],
  );
});

String _locationTypeKey(LocationType type) => switch (type) {
      LocationType.street => 'street',
      LocationType.yard => 'yard',
      LocationType.openLot => 'open_lot',
      LocationType.underground => 'underground',
      LocationType.multilevel => 'multilevel',
    };
