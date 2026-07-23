import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/navigation_deeplink.dart';
import '../../../../domain/models/route_result.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/nav_math.dart';

class RoutePreviewSheet extends ConsumerStatefulWidget {
  const RoutePreviewSheet({
    super.key,
    required this.route,
    this.zoneLat,
    this.zoneLon,
    this.onNavigateInApp,
    required this.onClose,
  });

  final ActiveRoute route;
  final double? zoneLat;
  final double? zoneLon;
  final VoidCallback? onNavigateInApp;
  final VoidCallback onClose;

  @override
  ConsumerState<RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends ConsumerState<RoutePreviewSheet> {
  bool _launching = false;

  String _formatArrival(String iso, AppStrings s) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final mins = dt.difference(DateTime.now()).inMinutes;
    if (mins > 0 && mins <= 90) return '${s.inWord} $mins ${s.minutesSign}';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _launchNavigator() async {
    setState(() => _launching = true);
    try {
      final url = widget.route.deeplinkUrl;
      final lat = widget.zoneLat;
      final lon = widget.zoneLon;
      if (lat != null && lon != null) {
        await openYandexMapsRoute(lat, lon);
      } else if (url != null) {
        await openYandexMapsUrl(url);
      } else {
        if (mounted) {
          final s = ref.read(l10nProvider);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.pointLookupError)));
        }
        return;
      }
    } catch (error, stackTrace) {
      if (mounted) {
        final s = ref.read(l10nProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.externalMapOpenError)));
        debugPrint('Failed to open Yandex Maps: $error\n$stackTrace');
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(l10nProvider);
    final selectedCandidates = widget.route.candidates.where(
      (candidate) => candidate.zoneId == widget.route.selectedZoneId,
    );
    final candidate =
        selectedCandidates.firstOrNull ?? widget.route.candidates.firstOrNull;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text(
                s.routeReady,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.route.arrivalTime != null)
                Text(
                  '${s.arrival}: ${_formatArrival(widget.route.arrivalTime!, s)}',
                ),
              if (candidate != null) ...[
                Builder(
                  builder: (_) {
                    final parts = <String>[];
                    if (candidate.distanceToDestinationMeters != null) {
                      parts.add(
                        formatNavDistance(
                          candidate.distanceToDestinationMeters!,
                          s,
                        ),
                      );
                    }
                    if (candidate.durationFromOriginSeconds != null) {
                      parts.add(
                        formatNavDuration(
                          candidate.durationFromOriginSeconds!,
                          s,
                        ),
                      );
                    }
                    if (parts.isEmpty) return const SizedBox.shrink();
                    return Text(
                      parts.join(' • '),
                      style: TextStyle(color: Theme.of(context).hintColor),
                    );
                  },
                ),
              ],
              const SizedBox(height: 18),
              if (widget.onNavigateInApp != null)
                FilledButton.icon(
                  onPressed: () {
                    widget.onNavigateInApp!();
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: Text(s.goAction),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.onNavigateInApp != null
                      ? Theme.of(context).colorScheme.surface
                      : null,
                  foregroundColor: widget.onNavigateInApp != null
                      ? AppColors.primary
                      : null,
                  side: widget.onNavigateInApp != null
                      ? const BorderSide(color: AppColors.primary)
                      : null,
                ),
                onPressed: _launching ? null : _launchNavigator,
                icon: const Icon(Icons.open_in_new),
                label: Text(_launching ? s.searching : s.openInYandexMaps),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onClose,
                child: Text(
                  s.reset,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
