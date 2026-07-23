import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/models/route_result.dart';
import '../../../../domain/models/zone.dart';
import '../../../providers/parking_address_provider.dart';
import '../../../providers/zones_provider.dart';
import 'parking_result_formatter.dart';
import 'parking_zone_layer.dart';

class ParkingCardSheet extends ConsumerWidget {
  const ParkingCardSheet({
    super.key,
    required this.zone,
    required this.onBuildRoute,
    required this.onClose,
    this.onOpenExternal,
    this.originLatitude,
    this.originLongitude,
    this.candidate,
    this.onBack,
    this.onPrevious,
    this.onNext,
    this.resultIndex,
    this.resultCount,
  });

  final Zone zone;
  final RouteCandidate? candidate;
  final VoidCallback onBuildRoute;
  final VoidCallback onClose;
  final VoidCallback? onOpenExternal;
  final double? originLatitude;
  final double? originLongitude;
  final VoidCallback? onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final int? resultIndex;
  final int? resultCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final zonesAsync = ref.watch(rawZonesProvider);
    final currentZone =
        zonesAsync.valueOrNull
            ?.where((item) => item.zoneId == zone.zoneId)
            .firstOrNull ??
        zone;
    final center = currentZone.geometry.isEmpty
        ? null
        : centroid(currentZone.geometry);
    final address = center == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(
            parkingAddressProvider((
              latitude: center.latitude,
              longitude: center.longitude,
            )),
          );
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      elevation: 14,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 8),
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: s.backToResults,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      address.when(
                        data: (value) => Text(
                          [
                            '${s.parkingNumber}${currentZone.zoneId}',
                            if (value != null && value.trim().isNotEmpty) value,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        loading: () => Text(
                          '${s.parkingNumber}${currentZone.zoneId} · ${s.addressLoading}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        error: (_, _) => Text(
                          '${s.parkingNumber}${currentZone.zoneId}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (resultIndex != null && resultCount != null)
                  Text(
                    '${resultIndex! + 1}/$resultCount',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                IconButton(
                  tooltip: s.close,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _AvailabilityFact(zone: currentZone, s: s),
                if (formatParkingPrice(currentZone.pay, s) case final price?)
                  _Fact(icon: Icons.payments_outlined, text: price),
                if (currentZone.locationType != null)
                  _Fact(
                    icon: Icons.place_outlined,
                    text: _locationTypeLabel(currentZone.locationType!, s),
                  ),
                if (currentZone.isAccessible == true)
                  _Fact(icon: Icons.accessible, text: s.accessibleParking),
                if (currentZone.isPrivate == true)
                  _Fact(icon: Icons.lock_outline, text: s.private),
                _Fact(
                  icon: Icons.verified_outlined,
                  text:
                      '${s.confidence}: ${(((candidate?.confidence ?? currentZone.confidence).clamp(0, 1)) * 100).round()}%',
                ),
              ],
            ),
            if (candidate != null) ...[
              const SizedBox(height: 10),
              _CandidateFacts(
                candidate: candidate!,
                zone: currentZone,
                originLatitude: originLatitude,
                originLongitude: originLongitude,
                s: s,
              ),
            ],
            if (onPrevious != null || onNext != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left),
                      label: Text(s.previousParking),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onNext,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right),
                      label: Text(s.nextParking),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onBuildRoute,
                    icon: const Icon(Icons.navigation_rounded),
                    label: Text(s.buildRoute),
                  ),
                ),
                if (onOpenExternal != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onOpenExternal,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(s.openInYandexMaps),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateFacts extends StatelessWidget {
  const _CandidateFacts({
    required this.candidate,
    required this.zone,
    required this.s,
    this.originLatitude,
    this.originLongitude,
  });

  final RouteCandidate candidate;
  final Zone zone;
  final AppStrings s;
  final double? originLatitude;
  final double? originLongitude;

  @override
  Widget build(BuildContext context) {
    final facts = <Widget>[];
    final duration = formatParkingDuration(
      candidate.durationFromOriginSeconds,
      s,
    );
    final origin = originLatitude == null || originLongitude == null
        ? null
        : Point(latitude: originLatitude!, longitude: originLongitude!);
    final center = zone.geometry.isEmpty ? null : centroid(zone.geometry);
    final routeDistance = formatParkingDistance(
      parkingPolylineLengthMeters(candidate.routePolyline) ??
          parkingPointDistanceMeters(origin, center),
      s,
    );
    final destinationDistance = formatParkingDistance(
      candidate.distanceToDestinationMeters,
      s,
    );
    final predicted = formatParkingSpaces(candidate.predictedFreeCount, s);
    final eta = formatParkingArrivalEstimate(
      candidate.eta,
      candidate.durationFromOriginSeconds,
    );
    if (routeDistance != null || duration != null) {
      facts.add(
        _Fact(
          icon: Icons.directions_car_outlined,
          text: [
            ?routeDistance,
            if (duration != null) '($duration)',
            s.fromYou,
          ].join(' '),
        ),
      );
    }
    if (destinationDistance != null) {
      facts.add(
        _Fact(
          icon: Icons.directions_walk,
          text:
              '$destinationDistance ${s.toDestination} · '
              '${formatParkingWalkingDuration(candidate.distanceToDestinationMeters, s)} '
              '${s.walkingTime}',
        ),
      );
    }
    if (predicted != null) {
      facts.add(
        _Fact(
          icon: Icons.auto_graph,
          text: eta == null
              ? '${s.forecast}: $predicted'
              : '${s.forecast}: $predicted ${s.expectedAvailability} $eta',
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 6, children: facts);
  }
}

class _AvailabilityFact extends StatelessWidget {
  const _AvailabilityFact({required this.zone, required this.s});

  final Zone zone;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (zone.freeCount) {
      <= 0 => colors.error,
      1 => const Color(0xFFB48409),
      _ => AppColors.primary,
    };
    final spaces = formatParkingSpaces(zone.freeCount, s) ?? s.noForecast;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_parking, size: 16, color: color),
          const SizedBox(width: 5),
          Text(spaces, style: TextStyle(fontSize: 12, color: color)),
          if (zone.capacity > 0) ...[
            const SizedBox(width: 3),
            Text(
              '/ ${zone.capacity}',
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: effectiveColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: effectiveColor),
            ),
          ),
        ],
      ),
    );
  }
}

String _locationTypeLabel(LocationType type, AppStrings s) => switch (type) {
  LocationType.street => s.street,
  LocationType.yard => s.yard,
  LocationType.openLot => s.openLot,
  LocationType.underground => s.underground,
  LocationType.multilevel => s.multilevel,
};
