import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../../../presentation/providers/time_selector_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';

class TimeSelectorWidget extends ConsumerWidget {
  const TimeSelectorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final timeMode = ref.watch(timeSelectorProvider);
    final isNow = timeMode.maybeWhen(now: () => true, orElse: () => false);
    final selectedDt = timeMode.maybeWhen(
      future: (at) => at,
      past: (at) => at,
      orElse: () => null,
    );

    void openPicker() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PointerInterceptor(
          intercepting: kIsWeb,
          child: _TimePickerSheet(
            initial: selectedDt,
            onApply: (dt) => _apply(ref, dt),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isNow) ...[
          _Chip(
            label: s.now,
            icon: Icons.restore,
            active: false,
            onTap: () => ref.read(timeSelectorProvider.notifier).setNow(),
          ),
          const SizedBox(height: 6),
        ],
        _Chip(
          label: isNow ? s.time : _selectionLabel(selectedDt!, s),
          icon: Icons.access_time_outlined,
          active: !isNow,
          onTap: openPicker,
        ),
      ],
    );
  }

  void _apply(WidgetRef ref, DateTime? dt) {
    if (dt == null) {
      ref.read(timeSelectorProvider.notifier).setNow();
      return;
    }
    final now = DateTime.now();
    final diff = dt.difference(now).inMinutes;
    if (diff.abs() < 15) {
      ref.read(timeSelectorProvider.notifier).setNow();
    } else if (diff < 0) {
      ref.read(timeSelectorProvider.notifier).setPast(dt);
    } else {
      ref.read(timeSelectorProvider.notifier).setFuture(dt);
    }
  }

  String _selectionLabel(DateTime dt, AppStrings s) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final time = '$h:$m';
    if (dtDay == DateTime(now.year, now.month, now.day)) {
      return '${s.today} $time';
    }
    if (dtDay == DateTime(tomorrow.year, tomorrow.month, tomorrow.day)) {
      return '${s.tomorrow} $time';
    }
    if (dtDay == DateTime(yesterday.year, yesterday.month, yesterday.day)) {
      return '${s.yesterday} $time';
    }

    return '${dt.day} ${s.monthNames[dt.month]} $time';
  }
}

// ─── Bottom sheet ───────────────────────────────────────────────────────────

class _TimePickerSheet extends ConsumerStatefulWidget {
  final DateTime? initial;
  final void Function(DateTime? dt) onApply;

  const _TimePickerSheet({required this.initial, required this.onApply});

  @override
  ConsumerState<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends ConsumerState<_TimePickerSheet> {
  static const _step = 30;

  late int _dayOffset; // -1 yesterday, 0 today, 1 tomorrow
  late DateTime _time;

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? DateTime.now();
    final today = _dayOnly(DateTime.now());
    final baseDay = _dayOnly(base);
    _dayOffset = baseDay.difference(today).inDays.clamp(-1, 1);
    _time = _snapTo30(base);
  }

  static DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static DateTime _snapTo30(DateTime dt) {
    final snapped = ((dt.minute / _step).round() * _step) % 60;
    final hourAdd = ((dt.minute / _step).round() * _step) ~/ 60;
    return DateTime(
      dt.year,
      dt.month,
      dt.day,
      (dt.hour + hourAdd) % 24,
      snapped,
    );
  }

  DateTime get _result {
    final base = _dayOnly(DateTime.now()).add(Duration(days: _dayOffset));
    return DateTime(base.year, base.month, base.day, _time.hour, _time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(l10nProvider);
    final days = [(-1, s.yesterday), (0, s.today), (1, s.tomorrow)];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            s.time,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          // Day
          Row(
            children: days.map((pair) {
              final (offset, label) = pair;
              final sel = _dayOffset == offset;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _dayOffset = offset),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: sel
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Time picker
          SizedBox(
            height: 150,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  ...ScrollConfiguration.of(context).dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Theme.of(context).brightness,
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: _step,
                  initialDateTime: _time,
                  onDateTimeChanged: (dt) {
                    setState(
                      () => _time = DateTime(
                        _time.year,
                        _time.month,
                        _time.day,
                        dt.hour,
                        dt.minute,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onApply(null);
                  },
                  child: Text(s.now),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onApply(_result);
                  },
                  child: Text(s.apply),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Chip ───────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = active
        ? AppColors.primary
        : Theme.of(context).dividerColor;
    final textColor = active
        ? AppColors.primary
        : Theme.of(context).colorScheme.onSurface;
    final iconColor = active ? AppColors.primary : Theme.of(context).hintColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: active ? 1.5 : 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
