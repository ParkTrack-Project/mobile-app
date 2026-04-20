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
  static const _step = Duration(minutes: 30);
  static const _hoursBefore = 24;
  static const _hoursAfter = 24;

  late final List<DateTime> _ticks;
  late final int _centerIndex;
  late final PageController _controller;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final alignedNow = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 0 : 30,
    );
    _ticks = [
      for (var i = -(_hoursBefore * 2); i <= _hoursAfter * 2; i++)
        alignedNow.add(_step * i),
    ];
    _centerIndex = _hoursBefore * 2;
    _selectedIndex = _centerIndex;
    _controller = PageController(
      viewportFraction: 0.17,
      initialPage: _centerIndex,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyTimeMode(_centerIndex);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyTimeMode(int index) {
    final selected = _ticks[index];
    final now = _ticks[_centerIndex];
    final notifier = ref.read(timeSelectorProvider.notifier);
    final diff = selected.difference(now).inMinutes;
    if (diff.abs() < 15) {
      notifier.setNow();
    } else if (diff < 0) {
      notifier.setPast(selected);
    } else {
      notifier.setFuture(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: PageView.builder(
        controller: _controller,
        physics: const BouncingScrollPhysics(),
        itemCount: _ticks.length,
        onPageChanged: (index) {
          if (_selectedIndex != index) {
            setState(() => _selectedIndex = index);
            _applyTimeMode(index);
          }
        },
        itemBuilder: (_, index) {
          final tick = _ticks[index];
          final isSelected = index == _selectedIndex;
          final isNow = index == _centerIndex;
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: isSelected ? 3 : 2,
                    height: isSelected ? 14 : 10,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isNow ? 'Сейчас' : _formatTick(tick),
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTick(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
