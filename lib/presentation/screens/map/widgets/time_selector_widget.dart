import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../presentation/providers/time_selector_provider.dart';
import '../../../../core/theme/app_colors.dart';

class TimeSelectorWidget extends ConsumerStatefulWidget {
  const TimeSelectorWidget({super.key});

  @override
  ConsumerState<TimeSelectorWidget> createState() => _TimeSelectorWidgetState();
}

class _TimeSelectorWidgetState extends ConsumerState<TimeSelectorWidget> {
  static const _itemWidth = 64.0;
  static const _step = Duration(minutes: 30);
  static const _hoursBefore = 24;
  static const _hoursAfter = 24;

  late final List<DateTime> _ticks;
  late final int _centerIndex;
  late final ScrollController _controller;
  Timer? _snapTimer;
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
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToIndex(_centerIndex);
      _applyTimeMode(_centerIndex);
    });
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _jumpToIndex(int index) {
    _controller.jumpTo(index * _itemWidth);
  }

  void _animateToIndex(int index) {
    _controller.animateTo(
      index * _itemWidth,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _onScrollEnd() {
    final rawIndex = (_controller.offset / _itemWidth).round();
    final clamped = rawIndex.clamp(0, _ticks.length - 1);
    _animateToIndex(clamped);
    if (_selectedIndex != clamped) {
      setState(() => _selectedIndex = clamped);
      _applyTimeMode(clamped);
    }
  }

  void _applyTimeMode(int index) {
    final selected = _ticks[index];
    final now = _ticks[_centerIndex];
    final notifier = ref.read(timeSelectorProvider.notifier);
    final diff = selected.difference(now).inMinutes;
    if (diff.abs() < 15) {
      notifier.setNow();
      return;
    }
    if (diff < 0) {
      notifier.setPast(selected);
    } else {
      notifier.setFuture(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                _onScrollEnd();
              } else if (notification is UserScrollNotification &&
                  notification.direction == ScrollDirection.idle) {
                _snapTimer?.cancel();
                _snapTimer = Timer(const Duration(milliseconds: 80), _onScrollEnd);
              }
              return false;
            },
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _ticks.length,
              itemBuilder: (_, index) {
                final tick = _ticks[index];
                final isSelected = index == _selectedIndex;
                final isNow = index == _centerIndex;
                return SizedBox(
                  width: _itemWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: isSelected ? 3 : 2,
                        height: isSelected ? 18 : 12,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isNow ? 'Сейчас' : _formatTick(tick),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          IgnorePointer(
            child: Container(
              width: _itemWidth,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                color: AppColors.primary.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTick(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
