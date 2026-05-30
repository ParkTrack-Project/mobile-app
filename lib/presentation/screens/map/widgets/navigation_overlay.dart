import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/nav_math.dart';
import '../../../providers/navigation_provider.dart';

class NavigationTurnCard extends ConsumerWidget {
  const NavigationTurnCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    if (nav == null) return const SizedBox.shrink();
    return _TurnCard(
      turn: nav.nextTurn,
      isOffRoute: nav.isOffRoute,
      hasArrived: nav.hasArrived,
    );
  }
}

class NavigationBottomBar extends ConsumerWidget {
  const NavigationBottomBar({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    if (nav == null) return const SizedBox.shrink();
    return _NavBottomBar(nav: nav, onFinish: onFinish);
  }
}

// ─── Turn instruction card ─────────────────────────────────────────────────

class _TurnCard extends StatelessWidget {
  const _TurnCard({required this.turn, required this.isOffRoute, required this.hasArrived});

  final NavTurn? turn;
  final bool isOffRoute;
  final bool hasArrived;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final IconData icon;
    final String primary;
    final String? secondary;

    if (hasArrived) {
      bg = AppColors.primary;
      icon = Icons.local_parking;
      primary = 'Вы прибыли';
      secondary = null;
    } else if (isOffRoute) {
      bg = Colors.orange.shade800;
      icon = Icons.warning_rounded;
      primary = 'Пересчёт маршрута...';
      secondary = null;
    } else if (turn != null) {
      final t = turn!;
      bg = AppColors.primary;
      icon = _turnIcon(t.direction);
      primary = _turnLabel(t.direction);
      secondary = 'через ${formatNavDistance(t.distanceMeters)}';
    } else {
      bg = AppColors.primary;
      icon = Icons.arrow_upward_rounded;
      primary = 'Движение прямо';
      secondary = null;
    }

    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      elevation: 6,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 20, 16),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: bg, size: 38),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      primary,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    if (secondary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        secondary,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _turnIcon(TurnDirection d) => switch (d) {
        TurnDirection.left => Icons.turn_left_rounded,
        TurnDirection.slightLeft => Icons.turn_slight_left_rounded,
        TurnDirection.right => Icons.turn_right_rounded,
        TurnDirection.slightRight => Icons.turn_slight_right_rounded,
        TurnDirection.uTurn => Icons.u_turn_left_rounded,
        TurnDirection.arrive => Icons.local_parking,
        TurnDirection.straight => Icons.arrow_upward_rounded,
      };

  String _turnLabel(TurnDirection d) => switch (d) {
        TurnDirection.left => 'Поверните налево',
        TurnDirection.slightLeft => 'Держитесь левее',
        TurnDirection.right => 'Поверните направо',
        TurnDirection.slightRight => 'Держитесь правее',
        TurnDirection.uTurn => 'Выполните разворот',
        TurnDirection.arrive => 'Вы прибыли',
        TurnDirection.straight => 'Движение прямо',
      };
}

// ─── Bottom stats bar ──────────────────────────────────────────────────────

class _NavBottomBar extends StatelessWidget {
  const _NavBottomBar({required this.nav, required this.onFinish});

  final NavigationData nav;
  final VoidCallback onFinish;

  void _confirmFinish(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Завершить маршрут?'),
        content: const Text('Навигация будет остановлена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onFinish();
            },
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speedColor = nav.speedKmh > 90 ? Colors.red.shade600 : AppColors.onSurface;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        12, 10, 4, MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              value: formatNavDuration(nav.remainingSeconds),
              label: 'времени',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCell(
              value: formatNavDistance(nav.remainingMeters),
              label: 'до цели',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCell(
              value: '${nav.speedKmh.round()}',
              label: 'км/ч',
              valueColor: speedColor,
            ),
          ),
          IconButton(
            onPressed: () => _confirmFinish(context),
            icon: const Icon(Icons.stop_circle_outlined),
            color: AppColors.textSecondary,
            iconSize: 28,
            tooltip: 'Завершить',
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.onSurface,
            height: 1,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
