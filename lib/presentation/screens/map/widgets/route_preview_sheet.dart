import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/navigation_deeplink.dart';
import '../../../../domain/models/route_result.dart';
import '../../../providers/routing_provider.dart';

class RoutePreviewSheet extends ConsumerStatefulWidget {
  const RoutePreviewSheet({super.key, required this.route});

  final ActiveRoute route;

  @override
  ConsumerState<RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends ConsumerState<RoutePreviewSheet> {
  bool _launching = false;

  Future<void> _launch() async {
    final url = widget.route.deeplinkUrl;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка на навигатор недоступна')),
      );
      return;
    }
    setState(() => _launching = true);
    try {
      await openYandexNavigatorUrl(url);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Text('Прибытие: ${widget.route.arrivalTime}'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _launching ? null : _launch,
              icon: const Icon(Icons.navigation_outlined),
              label: Text(_launching ? 'Открываем...' : 'Открыть в навигаторе'),
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
