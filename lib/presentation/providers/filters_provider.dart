import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'filters_provider.freezed.dart';

@freezed
class FiltersState with _$FiltersState {
  const factory FiltersState({
    @Default(false) bool hideNoFreeSpots,
    @Default(0.0) double minConfidence,
    int? maxPayPerHour,
    @Default(false) bool hidePrivate,
    @Default(false) bool hideInaccessible,
    @Default({}) Set<String> hiddenLocationTypes,
    @Default(true) bool hideInactive,
  }) = _FiltersState;
}

class FiltersNotifier extends StateNotifier<FiltersState> {
  FiltersNotifier() : super(const FiltersState());

  void toggleHideNoFreeSpots() =>
      state = state.copyWith(hideNoFreeSpots: !state.hideNoFreeSpots);

  void setMinConfidence(double value) =>
      state = state.copyWith(minConfidence: value);

  void setMaxPay(int? value) => state = state.copyWith(maxPayPerHour: value);

  void toggleHidePrivate() =>
      state = state.copyWith(hidePrivate: !state.hidePrivate);

  void toggleHideInaccessible() =>
      state = state.copyWith(hideInaccessible: !state.hideInaccessible);

  void toggleLocationType(String type) {
    final current = Set<String>.from(state.hiddenLocationTypes);
    if (current.contains(type)) {
      current.remove(type);
    } else {
      current.add(type);
    }
    state = state.copyWith(hiddenLocationTypes: current);
  }

  void toggleHideInactive() =>
      state = state.copyWith(hideInactive: !state.hideInactive);

  void reset() => state = const FiltersState();
}

final filtersProvider =
    StateNotifierProvider<FiltersNotifier, FiltersState>((ref) => FiltersNotifier());
