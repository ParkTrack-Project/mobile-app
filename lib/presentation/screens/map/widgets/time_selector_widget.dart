import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../presentation/providers/time_selector_provider.dart';
import '../../../../core/theme/app_colors.dart';

class TimeSelectorWidget extends ConsumerWidget {
  const TimeSelectorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        builder: (_) => _TimePickerSheet(
          initial: selectedDt,
          onApply: (dt) => _apply(ref, dt),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isNow) ...[
          _Chip(
            label: 'Сейчас',
            icon: Icons.restore,
            active: false,
            onTap: () => ref.read(timeSelectorProvider.notifier).setNow(),
          ),
          const SizedBox(height: 6),
        ],
        _Chip(
          label: isNow ? 'Время' : _selectionLabel(selectedDt!),
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

  String _selectionLabel(DateTime dt) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final time = '$h:$m';
    if (dtDay == DateTime(now.year, now.month, now.day)) return 'Сегодня $time';
    if (dtDay == DateTime(tomorrow.year, tomorrow.month, tomorrow.day)) return 'Завтра $time';
    if (dtDay == DateTime(yesterday.year, yesterday.month, yesterday.day)) return 'Вчера $time';
    const months = ['', 'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return '${dt.day} ${months[dt.month]} $time';
  }
}

// ─── Bottom sheet ───────────────────────────────────────────────────────────

class _TimePickerSheet extends StatefulWidget {
  final DateTime? initial;
  final void Function(DateTime? dt) onApply;

  const _TimePickerSheet({required this.initial, required this.onApply});

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  static const _step = 30;

  late int _dayOffset; // -1 вчера, 0 сегодня, 1 завтра
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
    return DateTime(dt.year, dt.month, dt.day, (dt.hour + hourAdd) % 24, snapped);
  }

  DateTime get _result {
    final base = _dayOnly(DateTime.now()).add(Duration(days: _dayOffset));
    return DateTime(base.year, base.month, base.day, _time.hour, _time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final days = [
      (-1, 'Вчера'),
      (0, 'Сегодня'),
      (1, 'Завтра'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Выбрать время',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          // День
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
                      color: sel ? AppColors.primary : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: sel ? Colors.white : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Барабан времени
          SizedBox(
            height: 150,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              minuteInterval: _step,
              initialDateTime: _time,
              onDateTimeChanged: (dt) {
                setState(() => _time = DateTime(
                      _time.year, _time.month, _time.day,
                      dt.hour, dt.minute,
                    ));
              },
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
                  child: const Text('Сейчас'),
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
                  child: const Text('Применить'),
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
    final borderColor = active ? AppColors.primary : Colors.grey.shade400;
    final textColor = active ? AppColors.primary : AppColors.onSurface;
    final iconColor = active ? AppColors.primary : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: active ? 1.5 : 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 3),
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
