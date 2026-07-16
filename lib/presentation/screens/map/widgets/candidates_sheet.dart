import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/models/route_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/nav_math.dart';

class _CandidateSubtitle extends ConsumerWidget {
  final RouteCandidate candidate;
  const _CandidateSubtitle({required this.candidate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    final parts = <String>[
      '${s.free}: ${candidate.freeCount}',
      candidate.pay == 0 ? s.free.toLowerCase() : '${candidate.pay} ₽/${s.hourSign}',
    ];
    if (candidate.distanceToDestinationMeters != null) {
      parts.add(formatNavDistance(candidate.distanceToDestinationMeters!, s));
    }
    if (candidate.durationFromOriginSeconds != null) {
      parts.add(formatNavDuration(candidate.durationFromOriginSeconds!, s));
    }
    if (candidate.predictedFreeCount != null) {
      parts.add('${s.forecast.toLowerCase()}: ${candidate.predictedFreeCount}');
    }
    return Text(parts.join(' • '), overflow: TextOverflow.ellipsis, maxLines: 2);
  }
}

class CandidatesSheet extends ConsumerStatefulWidget {
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
  ConsumerState<CandidatesSheet> createState() => _CandidatesSheetState();
}

class _CandidatesSheetState extends ConsumerState<CandidatesSheet> {
  bool _listMode = true;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(l10nProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            Text(
              s.selectParking,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(value: true, label: Text(s.list)),
                ButtonSegment<bool>(value: false, label: Text(s.map)),
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
                    title: Text('${s.parkingZone} #${candidate.zoneId}'),
                    subtitle: _CandidateSubtitle(candidate: candidate),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onSelectByList(candidate.zoneId),
                  ),
                ),
            ] else ...[
              Text(
                s.pickOnMapInstruction,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onSelectOnMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(s.pickOnMapAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
