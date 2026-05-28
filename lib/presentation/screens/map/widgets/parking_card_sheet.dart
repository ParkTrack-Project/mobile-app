import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../presentation/providers/time_selector_provider.dart';

Future<void> showParkingCard(
  BuildContext context,
  Zone zone, {
  VoidCallback? onBuildRoute,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ParkingCardSheet(zone: zone, onBuildRoute: onBuildRoute),
  );
}

class _ParkingCardSheet extends ConsumerWidget {
  final Zone zone;
  final VoidCallback? onBuildRoute;

  const _ParkingCardSheet({required this.zone, this.onBuildRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeMode = ref.watch(timeSelectorProvider);
    final isFuture = timeMode.maybeWhen(future: (_) => true, orElse: () => false);
    final userSelectedAt = timeMode.maybeWhen(future: (at) => at, orElse: () => null);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.75,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Парковка #${zone.zoneId}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (zone.isPrivate == true)
                  _Badge('Частная', Colors.orange),
                if (zone.isAccessible == true)
                  _Badge('♿', AppColors.primary),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.local_parking,
              label: 'Мест',
              value: zone.hasForecast
                  ? '${zone.freeCount} / ${zone.capacity} свободно'
                  : 'Нет прогноза',
              valueColor: zone.hasForecast ? null : AppColors.textSecondary,
            ),
            if (isFuture && zone.hasForecast && zone.forecastFor != null)
              _InfoRow(
                icon: Icons.schedule,
                label: 'Прогноз на',
                value: _formatDateTime(zone.forecastFor!),
              ),
            if (isFuture && zone.hasForecast && zone.forecastGeneratedAt != null)
              _InfoRow(
                icon: Icons.build_circle_outlined,
                label: 'Создан',
                value: _formatDateTime(zone.forecastGeneratedAt!),
              ),
            _InfoRow(
              icon: Icons.payments_outlined,
              label: 'Стоимость',
              value: zone.pay == 0 ? 'Бесплатно' : '${zone.pay} ₽/ч',
              valueColor: zone.pay == 0 ? AppColors.primary : null,
            ),
            _InfoRow(
              icon: Icons.verified_outlined,
              label: 'Уверенность',
              value: zone.confidenceLevel ?? '${(zone.confidence * 100).round()}%',
            ),
            if (zone.locationType != null)
              _InfoRow(
                icon: Icons.place_outlined,
                label: 'Тип',
                value: _locationTypeLabel(zone.locationType!),
              ),
            _InfoRow(
              icon: Icons.directions_car_outlined,
              label: 'Постановка',
              value: zone.zoneType == ZoneType.parallel ? 'Параллельная' : 'Обычная',
            ),
            if (!isFuture && zone.occupancyUpdatedAt != null)
              _InfoRow(
                icon: Icons.update,
                label: 'Обновлено',
                value: _formatDateTime(zone.occupancyUpdatedAt!),
              ),
            if (isFuture && zone.forecastFor != null && userSelectedAt != null)
              _StaleForecastBanner(
                forecastFor: zone.forecastFor!,
                userSelectedAt: userSelectedAt,
                onSnap: () {
                  ref.read(timeSelectorProvider.notifier).setFuture(zone.forecastFor!);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onBuildRoute?.call();
              },
              icon: const Icon(Icons.directions),
              label: const Text('Построить маршрут'),
            ),
          ],
        ),
      ),
    );
  }

  String _locationTypeLabel(LocationType type) => switch (type) {
        LocationType.street => 'Уличная',
        LocationType.yard => 'Дворовая',
        LocationType.openLot => 'Открытая стоянка',
        LocationType.underground => 'Подземная',
        LocationType.multilevel => 'Многоуровневая',
      };

  static String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    final now = DateTime.now();
    final timeStr = _formatTime(l);
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return 'Сегодня $timeStr';
    }
    return '${l.day} ${_monthName(l.month)} $timeStr';
  }

  static String _monthName(int m) => const [
        '',
        'янв',
        'фев',
        'мар',
        'апр',
        'май',
        'июн',
        'июл',
        'авг',
        'сен',
        'окт',
        'ноя',
        'дек'
      ][m];
}

class _StaleForecastBanner extends StatelessWidget {
  final DateTime forecastFor;
  final DateTime userSelectedAt;
  final VoidCallback onSnap;

  const _StaleForecastBanner({
    required this.forecastFor,
    required this.userSelectedAt,
    required this.onSnap,
  });

  @override
  Widget build(BuildContext context) {
    final diffMin = userSelectedAt.difference(forecastFor).inMinutes.abs();
    if (diffMin <= 30) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прогноз на ${_ParkingCardSheet._formatTime(forecastFor)}, '
            'вы выбрали ${_ParkingCardSheet._formatTime(userSelectedAt)}',
            style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade800,
                side: BorderSide(color: Colors.orange.shade400),
              ),
              onPressed: onSnap,
              child: const Text('Открыть ближайшее доступное'),
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
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: valueColor ?? AppColors.onSurface,
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
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
