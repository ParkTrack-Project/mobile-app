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

    Future<void> pickDate() async {
      final base = selectedDt ?? DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 30)),
        locale: const Locale('ru', 'RU'),
      );
      if (picked == null || !context.mounted) return;
      final current = selectedDt ?? DateTime.now();
      final dt = DateTime(picked.year, picked.month, picked.day, current.hour, current.minute);
      _apply(ref, dt);
    }

    Future<void> pickTime() async {
      final base = selectedDt ?? DateTime.now();
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      );
      if (picked == null || !context.mounted) return;
      final current = selectedDt ?? DateTime.now();
      final dt = DateTime(current.year, current.month, current.day, picked.hour, picked.minute);
      _apply(ref, dt);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isNow) ...[
          _Chip(
            label: 'Сейчас',
            icon: Icons.restore,
            active: false,
            onTap: () => ref.read(timeSelectorProvider.notifier).setNow(),
          ),
          const SizedBox(width: 6),
        ],
        _Chip(
          label: _dateLabel(selectedDt),
          icon: Icons.calendar_today_outlined,
          active: !isNow,
          onTap: pickDate,
        ),
        const SizedBox(width: 6),
        _Chip(
          label: _timeLabel(selectedDt),
          icon: Icons.access_time_outlined,
          active: !isNow,
          onTap: pickTime,
        ),
      ],
    );
  }

  void _apply(WidgetRef ref, DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now).inMinutes;
    final notifier = ref.read(timeSelectorProvider.notifier);
    if (diff.abs() < 15) {
      notifier.setNow();
    } else if (diff < 0) {
      notifier.setPast(dt);
    } else {
      notifier.setFuture(dt);
    }
  }

  String _dateLabel(DateTime? dt) {
    if (dt == null) {
      final now = DateTime.now();
      return _dayLabel(now);
    }
    return _dayLabel(dt);
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Сегодня';
    final tomorrow = now.add(const Duration(days: 1));
    if (dt.year == tomorrow.year && dt.month == tomorrow.month && dt.day == tomorrow.day) {
      return 'Завтра';
    }
    const months = ['', 'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return '${dt.day} ${months[dt.month]}';
  }

  String _timeLabel(DateTime? dt) {
    if (dt == null) return 'сейчас';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

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
    final bg = active ? AppColors.primary : Colors.white;
    final fg = active ? Colors.white : AppColors.onSurface;
    final iconColor = active ? Colors.white : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : Colors.grey.shade400,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
