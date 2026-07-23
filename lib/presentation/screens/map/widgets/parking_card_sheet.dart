import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../presentation/providers/time_selector_provider.dart';
import '../../../../presentation/providers/zones_provider.dart';
import '../../../../core/localization/app_localizations.dart';

enum ParkingCardResult { back, buildRoute }

Future<ParkingCardResult?> showParkingCard(
  BuildContext context,
  Zone zone, {
  bool showBackButton = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => PointerInterceptor(
      intercepting: kIsWeb,
      child: _ParkingCardSheet(zone: zone, showBackButton: showBackButton),
    ),
  );
}

class _ParkingCardSheet extends ConsumerWidget {
  final Zone zone;
  final bool showBackButton;

  const _ParkingCardSheet({required this.zone, required this.showBackButton});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final timeMode = ref.watch(timeSelectorProvider);
    final isFuture = timeMode.maybeWhen(
      future: (_) => true,
      orElse: () => false,
    );
    final isPast = timeMode.maybeWhen(past: (_) => true, orElse: () => false);
    final userSelectedAt = timeMode.maybeWhen(
      future: (at) => at,
      orElse: () => null,
    );

    final zonesAsync = ref.watch(rawZonesProvider);
    final isLoading = zonesAsync is AsyncLoading;
    final currentZone =
        zonesAsync.valueOrNull
            ?.where((z) => z.zoneId == zone.zoneId)
            .firstOrNull ??
        zone;

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Row(
                children: [
                  if (showBackButton)
                    IconButton(
                      tooltip: s.backToResults,
                      onPressed: () =>
                          Navigator.pop(context, ParkingCardResult.back),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      s.parkingZone,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (currentZone.isPrivate == true)
                    _Badge(s.private, Colors.orange),
                  if (currentZone.isAccessible == true)
                    _Badge('♿', AppColors.primary),
                ],
              ),
              const SizedBox(height: 12),
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      s.loadingData,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else ...[
                _InfoRow(
                  icon: Icons.local_parking,
                  label: s.capacity,
                  value: currentZone.hasForecast
                      ? '${currentZone.freeCount} / ${currentZone.capacity} ${s.free.toLowerCase()}'
                      : s.noForecast,
                  valueColor: currentZone.hasForecast
                      ? null
                      : AppColors.textSecondary,
                ),
                if (isFuture &&
                    currentZone.hasForecast &&
                    currentZone.forecastFor != null)
                  _InfoRow(
                    icon: Icons.schedule,
                    label: '${s.forecast} ${s.forWord}',
                    value: _formatDateTime(currentZone.forecastFor!, s),
                  ),
                if (isFuture &&
                    currentZone.hasForecast &&
                    currentZone.forecastGeneratedAt != null)
                  _InfoRow(
                    icon: Icons.build_circle_outlined,
                    label: s.generated,
                    value: _formatDateTime(currentZone.forecastGeneratedAt!, s),
                  ),
                _InfoRow(
                  icon: Icons.payments_outlined,
                  label: s.pay,
                  value: currentZone.pay == 0
                      ? s.free
                      : '${currentZone.pay} ₽/${s.hourSign}',
                  valueColor: currentZone.pay == 0 ? AppColors.primary : null,
                ),
                if (!isPast)
                  _InfoRow(
                    icon: Icons.verified_outlined,
                    label: s.confidence,
                    value: _confidenceLabel(currentZone),
                  ),
                if (currentZone.locationType != null)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: s.type,
                    value: _locationTypeLabel(currentZone.locationType!, s),
                  ),
                _InfoRow(
                  icon: Icons.directions_car_outlined,
                  label: s.parkingType,
                  value: currentZone.zoneType == ZoneType.parallel
                      ? s.parallel
                      : s.regular,
                ),
                if (!isPast && currentZone.occupancyUpdatedAt != null)
                  _InfoRow(
                    icon: Icons.update,
                    label: s.updatedAt,
                    value: _formatDateTime(currentZone.occupancyUpdatedAt!, s),
                  ),
                if (isFuture &&
                    currentZone.forecastFor != null &&
                    userSelectedAt != null)
                  _StaleForecastBanner(
                    forecastFor: currentZone.forecastFor!,
                    userSelectedAt: userSelectedAt,
                    s: s,
                    onSnap: () {
                      ref
                          .read(timeSelectorProvider.notifier)
                          .setFuture(currentZone.forecastFor!);
                      Navigator.pop(context);
                    },
                  ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context, ParkingCardResult.buildRoute);
                  },
                  icon: const Icon(Icons.directions),
                  label: Text(s.buildRoute),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _confidenceLabel(Zone z) => '${(z.confidence * 100).round()}%';

  String _locationTypeLabel(LocationType type, AppStrings s) => switch (type) {
    LocationType.street => s.street,
    LocationType.yard => s.yard,
    LocationType.openLot => s.openLot,
    LocationType.underground => s.underground,
    LocationType.multilevel => s.multilevel,
  };

  static String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateTime(DateTime dt, AppStrings s) {
    final l = dt.toLocal();
    final now = DateTime.now();
    final timeStr = _formatTime(l);
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return '${s.today} $timeStr';
    }
    return '${l.day} ${s.monthNames[l.month]} $timeStr';
  }
}

class _StaleForecastBanner extends StatelessWidget {
  final DateTime forecastFor;
  final DateTime userSelectedAt;
  final VoidCallback onSnap;
  final AppStrings s;

  const _StaleForecastBanner({
    required this.forecastFor,
    required this.userSelectedAt,
    required this.onSnap,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final diffMin = userSelectedAt.difference(forecastFor).inMinutes.abs();
    if (diffMin <= 30) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s.forecastFor} ${_ParkingCardSheet._formatTime(forecastFor)}, '
            '${s.youPicked} ${_ParkingCardSheet._formatTime(userSelectedAt)}',
            style: const TextStyle(color: Colors.orange, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
              ),
              onPressed: onSnap,
              child: Text(s.jumpToClosest),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).hintColor),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 14),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
