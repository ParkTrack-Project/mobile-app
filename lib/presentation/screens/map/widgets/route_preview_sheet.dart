import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/navigation_deeplink.dart';
import '../../../../domain/models/route_result.dart';
import '../../../providers/routing_provider.dart';

class RoutePreviewSheet extends ConsumerStatefulWidget {
  const RoutePreviewSheet({
    super.key,
    required this.route,
    this.zoneLat,
    this.zoneLon,
    this.onNavigateInApp,
  });

  final ActiveRoute route;
  final double? zoneLat;
  final double? zoneLon;
  final VoidCallback? onNavigateInApp;

  @override
  ConsumerState<RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends ConsumerState<RoutePreviewSheet> {
  bool _launching = false;

  String _formatArrival(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final mins = dt.difference(DateTime.now()).inMinutes;
    if (mins > 0 && mins <= 90) return 'через $mins мин';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDuration(int seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '~$mins мин';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '~${h}ч' : '~${h}ч ${m}мин';
  }

  Future<void> _launchNavigator() async {
    setState(() => _launching = true);
    try {
      final url = widget.route.deeplinkUrl;
      final lat = widget.zoneLat;
      final lon = widget.zoneLon;
      if (url != null) {
        await openYandexNavigatorUrl(url);
      } else if (lat != null && lon != null) {
        await openYandexNavigator(lat, lon);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет данных для навигации')),
          );
        }
        return;
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.route.candidates.firstOrNull;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.42,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Маршрут готов',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('Зона: #${widget.route.selectedZoneId}'),
            if (widget.route.arrivalTime != null)
              Text('Прибытие: ${_formatArrival(widget.route.arrivalTime!)}'),
            if (candidate != null) ...[
              Builder(builder: (_) {
                final parts = <String>[];
                if (candidate.distanceToDestinationMeters != null)
                  parts.add('${(candidate.distanceToDestinationMeters! / 1000).toStringAsFixed(1)} км');
                if (candidate.durationFromOriginSeconds != null)
                  parts.add(_formatDuration(candidate.durationFromOriginSeconds!));
                if (parts.isEmpty) return const SizedBox.shrink();
                return Text(parts.join(' • '),
                    style: const TextStyle(color: Color(0xFF666666)));
              }),
            ],
            const SizedBox(height: 18),
            if (widget.onNavigateInApp != null)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onNavigateInApp!();
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Маршрут в приложении'),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: widget.onNavigateInApp != null
                    ? Colors.white
                    : null,
                foregroundColor: widget.onNavigateInApp != null
                    ? AppColors.primary
                    : null,
                side: widget.onNavigateInApp != null
                    ? const BorderSide(color: AppColors.primary)
                    : null,
              ),
              onPressed: _launching ? null : _launchNavigator,
              icon: const Icon(Icons.navigation_outlined),
              label: Text(_launching ? 'Открываем...' : 'Яндекс Навигатор'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(routingProvider.notifier).reset();
                Navigator.pop(context);
              },
              child: const Text(
                'Сбросить',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
