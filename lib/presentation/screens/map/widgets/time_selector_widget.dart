import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../presentation/providers/time_selector_provider.dart';
import '../../../../core/theme/app_colors.dart';

class TimeSelectorWidget extends ConsumerStatefulWidget {
  const TimeSelectorWidget({super.key});

  @override
  ConsumerState<TimeSelectorWidget> createState() => _TimeSelectorWidgetState();
}

class _TimeSelectorWidgetState extends ConsumerState<TimeSelectorWidget> {
  DateTime? _selected;

  bool get _isNow => _selected == null;

  void _resetToNow() {
    setState(() => _selected = null);
    ref.read(timeSelectorProvider.notifier).setNow();
  }

  void _apply(DateTime dt) {
    setState(() => _selected = dt);
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

  Future<void> _pickDate() async {
    final base = _selected ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null) return;
    final current = _selected ?? DateTime.now();
    _apply(DateTime(picked.year, picked.month, picked.day, current.hour, current.minute));
  }

  Future<void> _pickTime() async {
    final base = _selected ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (picked == null) return;
    final current = _selected ?? DateTime.now();
    _apply(DateTime(current.year, current.month, current.day, picked.hour, picked.minute));
  }

  String _dateLabel() {
    if (_isNow) {
      final now = DateTime.now();
      return _dayLabel(now);
    }
    return _dayLabel(_selected!);
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

  String _timeLabel() {
    if (_isNow) return 'сейчас';
    final h = _selected!.hour.toString().padLeft(2, '0');
    final m = _selected!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isNow) ...[
          _Chip(
            label: 'Сейчас',
            icon: Icons.restore,
            onTap: _resetToNow,
            active: false,
          ),
          const SizedBox(width: 6),
        ],
        _Chip(
          label: _dateLabel(),
          icon: Icons.calendar_today_outlined,
          onTap: _pickDate,
          active: !_isNow,
        ),
        const SizedBox(width: 6),
        _Chip(
          label: _timeLabel(),
          icon: Icons.access_time_outlined,
          onTap: _pickTime,
          active: !_isNow,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.active,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? AppColors.primary : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
