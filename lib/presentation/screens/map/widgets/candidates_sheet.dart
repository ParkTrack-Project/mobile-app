import 'package:flutter/material.dart';
import '../../../../domain/models/route_result.dart';
import '../../../../core/theme/app_colors.dart';

class CandidatesSheet extends StatefulWidget {
  const CandidatesSheet({
    super.key,
    required this.candidates,
    required this.onSelectByList,
    required this.onSelectOnMap,
  });

  final List<RouteCandidate> candidates;
  final void Function(int zoneId) onSelectByList;
  final VoidCallback onSelectOnMap;

  @override
  State<CandidatesSheet> createState() => _CandidatesSheetState();
}

class _CandidatesSheetState extends State<CandidatesSheet> {
  bool _listMode = true;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
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
              'Выберите парковку',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: true, label: Text('Список')),
                ButtonSegment<bool>(value: false, label: Text('Карта')),
              ],
              selected: {_listMode},
              onSelectionChanged: (value) {
                setState(() => _listMode = value.first);
              },
            ),
            const SizedBox(height: 12),
            if (_listMode) ...[
              for (final candidate in widget.candidates)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    title: Text('Зона #${candidate.zoneId}'),
                    subtitle: Text(
                      'Свободно: ${candidate.freeCount} • '
                      'Цена: ${candidate.pay == 0 ? "бесплатно" : "${candidate.pay} ₽/ч"}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onSelectByList(candidate.zoneId),
                  ),
                ),
            ] else ...[
              const Text(
                'Нажмите «Выбирать на карте», затем тапните подходящую зону на карте.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onSelectOnMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Выбирать на карте'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
