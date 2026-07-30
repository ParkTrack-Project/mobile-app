import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/nav_math.dart';
import '../../../../core/localization/app_localizations.dart';
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

class _TurnCard extends ConsumerWidget {
  const _TurnCard({
    required this.turn,
    required this.isOffRoute,
    required this.hasArrived,
  });

  final NavTurn? turn;
  final bool isOffRoute;
  final bool hasArrived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final Color bg;
    final IconData icon;
    final String primary;
    final String? secondary;

    if (hasArrived) {
      bg = AppColors.primary;
      icon = Icons.local_parking;
      primary = s.arrival;
      secondary = null;
    } else if (isOffRoute) {
      bg = Colors.orange.shade800;
      icon = Icons.warning_rounded;
      primary = s.recalculating;
      secondary = null;
    } else if (turn != null) {
      final t = turn!;
      bg = AppColors.primary;
      icon = _turnIcon(t.direction);
      primary = _turnLabel(t.direction, s);
      secondary = '${s.inWord} ${formatNavDistance(t.distanceMeters, s)}';
    } else {
      bg = AppColors.primary;
      icon = Icons.arrow_upward_rounded;
      primary = s.straightAhead;
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

  String _turnLabel(TurnDirection d, AppStrings s) => switch (d) {
    TurnDirection.left => s.turnLeft,
    TurnDirection.slightLeft => s.keepLeft,
    TurnDirection.right => s.turnRight,
    TurnDirection.slightRight => s.keepRight,
    TurnDirection.uTurn => s.uTurn,
    TurnDirection.arrive => s.arrival,
    TurnDirection.straight => s.straightAhead,
  };
}

// ─── Bottom stats bar ──────────────────────────────────────────────────────

class _NavBottomBar extends ConsumerWidget {
  const _NavBottomBar({required this.nav, required this.onFinish});

  final NavigationData nav;
  final VoidCallback onFinish;

  void _confirmFinish(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (_) => PointerInterceptor(
        intercepting: kIsWeb,
        child: AlertDialog(
          title: Text(s.finishConfirmTitle),
          content: Text(s.finishConfirmContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                onFinish();
              },
              child: Text(s.finish),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final speedColor = nav.speedKmh > 90
        ? Colors.red.shade600
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        4,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              icon: Icons.schedule_rounded,
              semanticsLabel: s.timeLabel,
              value: formatNavDuration(nav.remainingSeconds, s),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCell(
              icon: Icons.route_rounded,
              semanticsLabel: s.distanceLabel,
              value: formatNavDistance(nav.remainingMeters, s),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCell(
              icon: Icons.speed_rounded,
              semanticsLabel: s.speedLabel,
              value: '${nav.speedKmh.round()} ${s.speedLabel}',
              valueColor: speedColor,
            ),
          ),
          IconButton(
            onPressed: () => _confirmFinish(context, s),
            icon: const Icon(Icons.stop_circle_outlined),
            color: Theme.of(context).hintColor,
            iconSize: 28,
            tooltip: s.finish,
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.semanticsLabel,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String semanticsLabel;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: semanticsLabel,
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
