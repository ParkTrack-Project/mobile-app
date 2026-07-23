import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/models/route_result.dart';
import '../../../../domain/models/zone.dart';
import 'parking_result_formatter.dart';

enum CandidateAction { go, openExternal }

enum ParkingResultsPanelState { loading, results, error }

class CandidatesSheet extends ConsumerStatefulWidget {
  const CandidatesSheet({
    super.key,
    required this.candidates,
    required this.zones,
    required this.lastViewedZoneId,
    required this.initialScrollOffset,
    required this.onSelect,
    required this.onAction,
    required this.onScrollOffsetChanged,
    required this.onClose,
    this.panelState = ParkingResultsPanelState.results,
  });

  final List<RouteCandidate> candidates;
  final List<Zone> zones;
  final int? lastViewedZoneId;
  final double initialScrollOffset;
  final void Function(int zoneId) onSelect;
  final void Function(
    CandidateAction action,
    RouteCandidate candidate,
    Zone? zone,
  )
  onAction;
  final ValueChanged<double> onScrollOffsetChanged;
  final VoidCallback onClose;
  final ParkingResultsPanelState panelState;

  @override
  ConsumerState<CandidatesSheet> createState() => _CandidatesSheetState();
}

class _CandidatesSheetState extends ConsumerState<CandidatesSheet> {
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: widget.initialScrollOffset,
  );

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      widget.onScrollOffsetChanged(_scrollController.offset);
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(l10nProvider);
    final zonesById = {for (final zone in widget.zones) zone.zoneId: zone};
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      elevation: 14,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.parkingNearby,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: s.close,
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  s.rankingPrinciple,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: switch (widget.panelState) {
              ParkingResultsPanelState.loading => _PanelMessage(
                key: const Key('parking_search_loading'),
                icon: const CircularProgressIndicator(),
                message: s.searching,
              ),
              ParkingResultsPanelState.error => _PanelMessage(
                key: const Key('parking_search_error'),
                icon: Icon(Icons.error_outline, color: colors.error),
                message: s.searchError,
              ),
              ParkingResultsPanelState.results when widget.candidates.isEmpty =>
                _PanelMessage(
                  key: const Key('parking_search_empty'),
                  icon: Icon(
                    Icons.local_parking_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                  message: s.searchNoResults,
                ),
              ParkingResultsPanelState.results =>
                NotificationListener<ScrollEndNotification>(
                  onNotification: (_) {
                    widget.onScrollOffsetChanged(_scrollController.offset);
                    return false;
                  },
                  child: ListView.separated(
                    key: const Key('parking_search_results'),
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: widget.candidates.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                    itemBuilder: (context, index) {
                      final candidate = widget.candidates[index];
                      return _CandidateTile(
                        key: Key('parking_candidate_${candidate.zoneId}'),
                        candidate: candidate,
                        zone: zonesById[candidate.zoneId],
                        isLastViewed:
                            candidate.zoneId == widget.lastViewedZoneId,
                        s: s,
                        onTap: () => widget.onSelect(candidate.zoneId),
                        onAction: (action) => widget.onAction(
                          action,
                          candidate,
                          zonesById[candidate.zoneId],
                        ),
                      );
                    },
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    super.key,
    required this.candidate,
    required this.zone,
    required this.isLastViewed,
    required this.s,
    required this.onTap,
    required this.onAction,
  });

  final RouteCandidate candidate;
  final Zone? zone;
  final bool isLastViewed;
  final AppStrings s;
  final VoidCallback onTap;
  final ValueChanged<CandidateAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final durationText = formatParkingDuration(
      candidate.durationFromOriginSeconds,
      s,
    );
    final distanceText = formatParkingDistance(
      candidate.distanceToDestinationMeters,
      s,
    );
    final spacesText = formatParkingSpaces(candidate.freeCount, s);
    final priceText = formatParkingPrice(candidate.pay, s);
    final predictedSpacesText = formatParkingSpaces(
      candidate.predictedFreeCount,
      s,
    );
    final timeColor = switch (candidate.durationFromOriginSeconds) {
      null => colors.onSurfaceVariant,
      < 300 => AppColors.primary,
      < 600 => Colors.orange.shade700,
      _ => colors.error,
    };

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: isLastViewed
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (durationText != null)
              Container(
                constraints: const BoxConstraints(minWidth: 48),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: timeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  durationText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: timeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (durationText != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.parkingZone,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (distanceText != null)
                        _Fact(icon: Icons.route_outlined, text: distanceText),
                      if (spacesText != null)
                        _Fact(
                          icon: Icons.local_parking,
                          text: spacesText,
                          color: candidate.freeCount > 0
                              ? AppColors.primary
                              : colors.error,
                        ),
                      if (priceText != null)
                        _Fact(icon: Icons.payments_outlined, text: priceText),
                      if (predictedSpacesText != null)
                        _Fact(
                          icon: Icons.auto_graph,
                          text: '${s.forecast}: $predictedSpacesText',
                        ),
                      if (zone?.isPrivate == true)
                        _Fact(icon: Icons.lock_outline, text: s.private),
                      if (zone?.isAccessible == true)
                        _Fact(
                          icon: Icons.accessible,
                          text: s.accessibleParking,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<CandidateAction>(
              key: Key('parking_candidate_action_${candidate.zoneId}'),
              tooltip: s.moreInfo,
              onSelected: onAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: CandidateAction.go,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.navigation_outlined),
                    title: Text(s.goAction),
                  ),
                ),
                PopupMenuItem(
                  value: CandidateAction.openExternal,
                  enabled: zone?.geometry.isNotEmpty == true,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new),
                    title: Text(s.openInYandexMaps),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({super.key, required this.icon, required this.message});

  final Widget icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: 32, child: Center(child: icon)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: effectiveColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 12,
                fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
