import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/route_result.dart';

enum ParkingSearchView {
  hidden,
  loading,
  results,
  details,
  routeBuilding,
  error,
}

class ParkingSearchState {
  const ParkingSearchState({
    this.candidates = const [],
    this.view = ParkingSearchView.hidden,
    this.selectedZoneId,
    this.lastViewedZoneId,
    this.scrollOffset = 0,
  });

  final List<RouteCandidate> candidates;
  final ParkingSearchView view;
  final int? selectedZoneId;
  final int? lastViewedZoneId;
  final double scrollOffset;

  Set<int> get resultZoneIds =>
      candidates.map((candidate) => candidate.zoneId).toSet();

  ParkingSearchState copyWith({
    List<RouteCandidate>? candidates,
    ParkingSearchView? view,
    int? selectedZoneId,
    bool clearSelection = false,
    int? lastViewedZoneId,
    double? scrollOffset,
  }) => ParkingSearchState(
    candidates: candidates ?? this.candidates,
    view: view ?? this.view,
    selectedZoneId: clearSelection
        ? null
        : selectedZoneId ?? this.selectedZoneId,
    lastViewedZoneId: lastViewedZoneId ?? this.lastViewedZoneId,
    scrollOffset: scrollOffset ?? this.scrollOffset,
  );
}

class ParkingSearchNotifier extends StateNotifier<ParkingSearchState> {
  ParkingSearchNotifier() : super(const ParkingSearchState());

  void startSearch() {
    state = const ParkingSearchState(view: ParkingSearchView.loading);
  }

  void showResults(List<RouteCandidate> candidates) {
    final previousIds = state.candidates
        .map((candidate) => candidate.zoneId)
        .toList(growable: false);
    final nextIds = candidates
        .map((candidate) => candidate.zoneId)
        .toList(growable: false);
    final sameResults =
        previousIds.length == nextIds.length &&
        previousIds.indexed.every((entry) => entry.$2 == nextIds[entry.$1]);
    state = ParkingSearchState(
      candidates: List.unmodifiable(candidates),
      view: ParkingSearchView.results,
      lastViewedZoneId: sameResults ? state.lastViewedZoneId : null,
      scrollOffset: sameResults ? state.scrollOffset : 0,
    );
  }

  bool showDetails(int zoneId) {
    if (!state.resultZoneIds.contains(zoneId)) return false;
    state = state.copyWith(
      view: ParkingSearchView.details,
      selectedZoneId: zoneId,
      lastViewedZoneId: zoneId,
    );
    return true;
  }

  int? showAdjacent(int delta) {
    final selected = state.selectedZoneId;
    if (selected == null || delta == 0) return null;
    final index = state.candidates.indexWhere(
      (candidate) => candidate.zoneId == selected,
    );
    final nextIndex = index + delta;
    if (index < 0 || nextIndex < 0 || nextIndex >= state.candidates.length) {
      return null;
    }
    final nextId = state.candidates[nextIndex].zoneId;
    showDetails(nextId);
    return nextId;
  }

  void backToResults() {
    if (state.candidates.isEmpty) return;
    state = state.copyWith(
      view: ParkingSearchView.results,
      clearSelection: true,
    );
  }

  void startRoute(int zoneId) {
    if (!state.resultZoneIds.contains(zoneId)) return;
    state = state.copyWith(
      view: ParkingSearchView.routeBuilding,
      selectedZoneId: zoneId,
      lastViewedZoneId: zoneId,
    );
  }

  void hidePanel({int? lastViewedZoneId}) {
    state = state.copyWith(
      view: ParkingSearchView.hidden,
      clearSelection: true,
      lastViewedZoneId: lastViewedZoneId,
    );
  }

  void showSearchError() {
    state = const ParkingSearchState(view: ParkingSearchView.error);
  }

  void saveScrollOffset(double offset) {
    if (!offset.isFinite) return;
    state = state.copyWith(scrollOffset: offset < 0 ? 0 : offset);
  }

  void clear() => state = const ParkingSearchState();
}

final parkingSearchProvider =
    StateNotifierProvider<ParkingSearchNotifier, ParkingSearchState>(
      (_) => ParkingSearchNotifier(),
    );
