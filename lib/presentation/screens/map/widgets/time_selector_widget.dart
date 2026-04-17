import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../presentation/providers/time_selector_provider.dart';
import '../../../../core/theme/app_colors.dart';

class TimeSelectorWidget extends ConsumerWidget {
  const TimeSelectorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(timeSelectorProvider);
    final now = DateTime.now();

    final isNow = mode.maybeWhen(now: () => true, orElse: () => false);
    final isPast = mode.maybeWhen(past: (_) => true, orElse: () => false);
    final isFuture = mode.maybeWhen(future: (_) => true, orElse: () => false);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeButton(
            label: '−2ч',
            onTap: () => ref
                .read(timeSelectorProvider.notifier)
                .setPast(now.subtract(const Duration(hours: 2))),
            active: isPast,
          ),
          const SizedBox(width: 4),
          _TimeButton(
            label: 'Сейчас',
            onTap: () => ref.read(timeSelectorProvider.notifier).setNow(),
            active: isNow,
            primary: true,
          ),
          const SizedBox(width: 4),
          _TimeButton(
            label: '+1ч',
            onTap: () => ref
                .read(timeSelectorProvider.notifier)
                .setFuture(now.add(const Duration(hours: 1))),
            active: isFuture,
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool primary;

  const _TimeButton({
    required this.label,
    required this.onTap,
    this.active = false,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.onSurface,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
