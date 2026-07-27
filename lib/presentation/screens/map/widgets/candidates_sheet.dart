import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/models/route_result.dart';
import '../../../../domain/models/zone.dart';
import '../../../providers/parking_address_provider.dart';
import 'parking_zone_layer.dart';
import 'parking_result_formatter.dart';

enum CandidateAction { go, openExternal }

enum ParkingResultsPanelState { loading, results, routeBuilding, error }

const _resultsHeaderHeight = 114.0;
const _androidCandidateAddressFontSize = 12.0;
const _androidCandidateAddressMaxLines = 3;
const _androidCandidateAddressLineHeight = 1.15;

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
    this.originLatitude,
    this.originLongitude,
    this.hasDestination = false,
    this.onPanelHeightChanged,
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
  final double? originLatitude;
  final double? originLongitude;
  final bool hasDestination;
  final ValueChanged<double>? onPanelHeightChanged;
  final ParkingResultsPanelState panelState;

  @override
  ConsumerState<CandidatesSheet> createState() => _CandidatesSheetState();
}

class _CandidatesSheetState extends ConsumerState<CandidatesSheet> {
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: widget.initialScrollOffset,
  );
  double? _panelHeight;

  void _setPanelHeight(double value, double minHeight, double maxHeight) {
    final next = value.clamp(minHeight, maxHeight);
    if (next == _panelHeight) return;
    setState(() => _panelHeight = next);
    widget.onPanelHeightChanged?.call(next);
  }

  void _updatePanelHeightFromDrag({
    required double deltaY,
    required double fallbackHeight,
    required double minHeight,
    required double maxHeight,
  }) {
    _setPanelHeight(
      (_panelHeight ?? fallbackHeight) - deltaY * 1.5,
      minHeight,
      maxHeight,
    );
  }

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
    final resultTiers = relativeParkingResultTiers(
      widget.candidates,
      hasDestination: widget.hasDestination,
    );
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight < 280
            ? constraints.maxHeight
            : (constraints.maxHeight * 0.86).clamp(
                240.0,
                constraints.maxHeight,
              );
        final minHeight = mathMin(_resultsHeaderHeight + 56.0, maxHeight);
        final initialHeight = (constraints.maxHeight * 0.54).clamp(
          minHeight,
          maxHeight,
        );
        final panelHeight = (_panelHeight ?? initialHeight).clamp(
          minHeight,
          maxHeight,
        );
        if (_panelHeight == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _panelHeight == null) {
              setState(() => _panelHeight = initialHeight);
              widget.onPanelHeightChanged?.call(initialHeight);
            }
          });
        }

        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelHeight,
              child: PointerInterceptor(
                intercepting: kIsWeb,
                child: Material(
                  color: colors.surface,
                  elevation: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        key: const Key('parking_results_drag_header'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) =>
                            _updatePanelHeightFromDrag(
                              deltaY: details.delta.dy,
                              fallbackHeight: panelHeight,
                              minHeight: minHeight,
                              maxHeight: maxHeight,
                            ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
                              child: Center(
                                child: Container(
                                  key: const Key('parking_results_drag_handle'),
                                  width: 42,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: colors.outlineVariant,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.parkingNearby,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
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
                          ParkingResultsPanelState.routeBuilding =>
                            _PanelMessage(
                              key: const Key('parking_route_building'),
                              icon: const CircularProgressIndicator(),
                              message: s.routeBuilding,
                            ),
                          ParkingResultsPanelState.error => _PanelMessage(
                            key: const Key('parking_search_error'),
                            icon: Icon(
                              Icons.error_outline,
                              color: colors.error,
                            ),
                            message: s.searchError,
                          ),
                          ParkingResultsPanelState.results
                              when widget.candidates.isEmpty =>
                            _PanelMessage(
                              key: const Key('parking_search_empty'),
                              icon: Icon(
                                Icons.local_parking_outlined,
                                color: colors.onSurfaceVariant,
                              ),
                              message: s.searchNoResults,
                            ),
                          ParkingResultsPanelState.results =>
                            NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollEndNotification) {
                                  widget.onScrollOffsetChanged(
                                    _scrollController.offset,
                                  );
                                }
                                return false;
                              },
                              child: Builder(
                                builder: (context) {
                                  final hasLongDuration = widget.candidates.any(
                                    (c) {
                                      final text = formatParkingDuration(
                                        c.durationFromOriginSeconds,
                                        s,
                                      );
                                      return text?.contains(s.hourSign) ??
                                          false;
                                    },
                                  );
                                  final badgeWidth = hasLongDuration
                                      ? 88.0
                                      : 72.0;

                                  return ListView.separated(
                                    key: const Key('parking_search_results'),
                                    controller: _scrollController,
                                    padding: const EdgeInsets.only(bottom: 16),
                                    itemCount: widget.candidates.length,
                                    separatorBuilder: (_, _) => Divider(
                                      height: 1,
                                      indent: 20,
                                      endIndent: 20,
                                      color: colors.outlineVariant.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    itemBuilder: (context, index) {
                                      final candidate =
                                          widget.candidates[index];

                                      return _CandidateTile(
                                        key: Key(
                                          'parking_candidate_${candidate.zoneId}',
                                        ),
                                        candidate: candidate,
                                        zone: zonesById[candidate.zoneId],
                                        resultTier: resultTiers[index],
                                        hasDestination: widget.hasDestination,
                                        originLatitude: widget.originLatitude,
                                        originLongitude: widget.originLongitude,
                                        isLastViewed:
                                            candidate.zoneId ==
                                            widget.lastViewedZoneId,
                                        s: s,
                                        badgeWidth: badgeWidth,
                                        onTap: () =>
                                            widget.onSelect(candidate.zoneId),
                                        onAction: (action) => widget.onAction(
                                          action,
                                          candidate,
                                          zonesById[candidate.zoneId],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

double mathMin(double left, double right) => left < right ? left : right;

class _CandidateTile extends ConsumerWidget {
  const _CandidateTile({
    super.key,
    required this.candidate,
    required this.zone,
    required this.resultTier,
    required this.hasDestination,
    required this.isLastViewed,
    required this.s,
    required this.badgeWidth,
    required this.onTap,
    required this.onAction,
    this.originLatitude,
    this.originLongitude,
  });

  final RouteCandidate candidate;
  final Zone? zone;
  final ParkingResultTier resultTier;
  final bool hasDestination;
  final double? originLatitude;
  final double? originLongitude;
  final bool isLastViewed;
  final AppStrings s;
  final double badgeWidth;
  final VoidCallback onTap;
  final ValueChanged<CandidateAction> onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final durationText = formatParkingDuration(
      candidate.durationFromOriginSeconds,
      s,
    );
    final destinationDistanceText = formatParkingDistance(
      candidate.distanceToDestinationMeters,
      s,
    );
    final origin = originLatitude == null || originLongitude == null
        ? null
        : Point(latitude: originLatitude!, longitude: originLongitude!);
    final zoneCenter = zone == null || zone!.geometry.isEmpty
        ? null
        : centroid(zone!.geometry);
    final drivingDistanceText = formatParkingDistance(
      parkingPolylineLengthMeters(candidate.routePolyline) ??
          parkingPointDistanceMeters(origin, zoneCenter),
      s,
    );
    final walkingText = formatParkingWalkingDuration(
      candidate.distanceToDestinationMeters,
      s,
    );
    final displayedFreeCount = zone?.hasForecast == true
        ? zone?.freeCount
        : candidate.freeCount;
    final spacesText = formatParkingSpaces(displayedFreeCount, s);
    final priceText = formatParkingPrice(zone?.pay ?? candidate.pay, s);
    final predictedSpacesText = formatParkingSpaces(
      candidate.predictedFreeCount,
      s,
    );
    final arrivalText = formatParkingArrivalEstimate(
      candidate.eta,
      candidate.durationFromOriginSeconds,
    );
    final address = zone == null || zone!.geometry.isEmpty
        ? const AsyncValue<String?>.data(null)
        : ref.watch(
            parkingAddressProvider((
              latitude: centroid(zone!.geometry).latitude,
              longitude: centroid(zone!.geometry).longitude,
            )),
          );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useAndroidCandidateLayout =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final timeColor = switch (resultTier) {
      ParkingResultTier.good =>
        isDark ? const Color(0xFF81C784) : AppColors.primary,
      ParkingResultTier.average => const Color(0xFFB48409),
      ParkingResultTier.poor => isDark ? const Color(0xFFF44336) : colors.error,
    };

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: isLastViewed
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((hasDestination && destinationDistanceText != null) ||
                    (!hasDestination && durationText != null))
                  Container(
                    constraints: BoxConstraints(minWidth: badgeWidth),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: timeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if ((hasDestination &&
                                destinationDistanceText != null) ||
                            (!hasDestination && durationText != null))
                          Text(
                            hasDestination
                                ? destinationDistanceText!
                                : durationText!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: timeColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          hasDestination
                              ? '${walkingText ?? ''} ${s.walkingTime}'.trim()
                              : s.drivingTime,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: timeColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (useAndroidCandidateLayout && spacesText != null) ...[
                  const SizedBox(height: 6),
                  _AvailabilityBadge(
                    key: Key('parking_candidate_spaces_${candidate.zoneId}'),
                    text: spacesText,
                    freeCount: displayedFreeCount,
                  ),
                ],
              ],
            ),
            if ((hasDestination && destinationDistanceText != null) ||
                (!hasDestination && durationText != null) ||
                (useAndroidCandidateLayout && spacesText != null))
              const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  address.when(
                    data: (value) => Text(
                      useAndroidCandidateLayout
                          ? (value?.trim().isNotEmpty == true
                                ? value!.trim()
                                : '')
                          : [
                              '${s.parkingNumber}${candidate.zoneId}',
                              if (value != null && value.trim().isNotEmpty)
                                value.trim(),
                            ].join(' · '),
                      maxLines: useAndroidCandidateLayout
                          ? _androidCandidateAddressMaxLines
                          : 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: useAndroidCandidateLayout,
                      style: TextStyle(
                        fontSize: useAndroidCandidateLayout
                            ? _androidCandidateAddressFontSize
                            : 15,
                        fontWeight: useAndroidCandidateLayout
                            ? FontWeight.w500
                            : FontWeight.w600,
                        height: useAndroidCandidateLayout
                            ? _androidCandidateAddressLineHeight
                            : null,
                      ),
                    ),
                    loading: () => Text(
                      useAndroidCandidateLayout
                          ? s.addressLoading
                          : '${s.parkingNumber}${candidate.zoneId} · '
                                '${s.addressLoading}',
                      maxLines: useAndroidCandidateLayout
                          ? _androidCandidateAddressMaxLines
                          : 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: useAndroidCandidateLayout,
                      style: TextStyle(
                        fontSize: useAndroidCandidateLayout
                            ? _androidCandidateAddressFontSize
                            : null,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    error: (_, _) => Text(
                      useAndroidCandidateLayout
                          ? ''
                          : '${s.parkingNumber}${candidate.zoneId}',
                      style: TextStyle(
                        fontSize: useAndroidCandidateLayout
                            ? _androidCandidateAddressFontSize
                            : null,
                        fontWeight: useAndroidCandidateLayout
                            ? FontWeight.w500
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (useAndroidCandidateLayout)
                        _ParkingNumberBadge(
                          key: Key(
                            'parking_candidate_number_${candidate.zoneId}',
                          ),
                          zoneId: candidate.zoneId,
                        ),
                      if (!useAndroidCandidateLayout && spacesText != null)
                        _Fact(
                          icon: Icons.local_parking,
                          text: spacesText,
                          color: switch (displayedFreeCount) {
                            null => null,
                            <= 0 => colors.error,
                            1 => const Color(0xFFB48409),
                            _ => AppColors.primary,
                          },
                        ),
                      if (priceText != null)
                        _Fact(icon: Icons.payments_outlined, text: priceText),
                      if (predictedSpacesText != null)
                        _Fact(
                          icon: Icons.auto_graph,
                          text: arrivalText == null
                              ? '${s.forecast}: $predictedSpacesText'
                              : '${s.forecast}: $predictedSpacesText '
                                    '${s.expectedAvailability} $arrivalText',
                        ),
                      if (drivingDistanceText != null || durationText != null)
                        _Fact(
                          icon: Icons.directions_car_outlined,
                          text: [
                            ?drivingDistanceText,
                            if (durationText != null) '($durationText)',
                            s.fromYou,
                          ].join(' '),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  key: Key('parking_candidate_go_${candidate.zoneId}'),
                  tooltip: s.goAction,
                  constraints: const BoxConstraints.tightFor(
                    width: 46,
                    height: 46,
                  ),
                  onPressed: () => onAction(CandidateAction.go),
                  icon: const Icon(Icons.navigation_rounded),
                ),
                const SizedBox(width: 4),
                IconButton.outlined(
                  key: Key('parking_candidate_yandex_${candidate.zoneId}'),
                  tooltip: s.openInYandexMaps,
                  constraints: const BoxConstraints.tightFor(
                    width: 46,
                    height: 46,
                  ),
                  onPressed: zone?.geometry.isNotEmpty == true
                      ? () => onAction(CandidateAction.openExternal)
                      : null,
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    color: Color(0xFFE53935),
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

enum ParkingResultTier { good, average, poor }

List<ParkingResultTier> relativeParkingResultTiers(
  List<RouteCandidate> candidates, {
  required bool hasDestination,
}) {
  if (candidates.isEmpty) return const [];
  if (candidates.length == 1) return const [ParkingResultTier.good];
  final ranked = candidates.indexed.toList()
    ..sort((left, right) {
      final leftMetric = hasDestination
          ? left.$2.distanceToDestinationMeters
          : left.$2.durationFromOriginSeconds;
      final rightMetric = hasDestination
          ? right.$2.distanceToDestinationMeters
          : right.$2.durationFromOriginSeconds;
      if (leftMetric == null && rightMetric == null) return left.$1 - right.$1;
      if (leftMetric == null) return 1;
      if (rightMetric == null) return -1;
      final metricOrder = leftMetric.compareTo(rightMetric);
      return metricOrder == 0 ? left.$1 - right.$1 : metricOrder;
    });
  final result = List.filled(candidates.length, ParkingResultTier.average);
  for (var position = 0; position < ranked.length; position++) {
    final fraction = position / (ranked.length - 1);
    result[ranked[position].$1] = fraction <= 0.33
        ? ParkingResultTier.good
        : fraction >= 0.67
        ? ParkingResultTier.poor
        : ParkingResultTier.average;
  }
  return result;
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

class _ParkingNumberBadge extends StatelessWidget {
  const _ParkingNumberBadge({super.key, required this.zoneId});

  final int zoneId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDDF4FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '№$zoneId',
        style: const TextStyle(
          color: Color(0xFF0866A8),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({
    super.key,
    required this.text,
    required this.freeCount,
  });

  final String text;
  final int? freeCount;

  Color _textColor(ColorScheme colors) {
    final count = freeCount;
    if (count == null) return colors.onSurfaceVariant;
    if (count <= 0) return colors.error;
    if (count == 1) return const Color(0xFFB48409);
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _textColor(colors),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
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
