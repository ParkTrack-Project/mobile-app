import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/theme/app_colors.dart';

void showParkingCard(BuildContext context, WidgetRef ref, Zone zone) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ParkingCardSheet(zone: zone, ref: ref),
  );
}

class _ParkingCardSheet extends StatelessWidget {
  final Zone zone;
  final WidgetRef ref;

  const _ParkingCardSheet({required this.zone, required this.ref});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
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
              value: '${zone.freeCount} / ${zone.capacity} свободно',
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
            if (zone.occupancyUpdatedAt != null)
              _InfoRow(
                icon: Icons.update,
                label: 'Обновлено',
                value: _formatTime(zone.occupancyUpdatedAt!),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Store selected zone for routing
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

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
