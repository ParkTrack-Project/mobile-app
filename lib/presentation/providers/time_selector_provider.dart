import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'time_selector_provider.freezed.dart';

@freezed
class TimeMode with _$TimeMode {
  const factory TimeMode.now() = _Now;
  const factory TimeMode.past(DateTime at) = _Past;
  const factory TimeMode.future(DateTime at) = _Future;
}

class TimeSelectorNotifier extends StateNotifier<TimeMode> {
  TimeSelectorNotifier() : super(const TimeMode.now());

  void setNow() => state = const TimeMode.now();
  void setPast(DateTime at) => state = TimeMode.past(at);
  void setFuture(DateTime at) => state = TimeMode.future(at);
}

final timeSelectorProvider =
    StateNotifierProvider<TimeSelectorNotifier, TimeMode>(
        (ref) => TimeSelectorNotifier());
