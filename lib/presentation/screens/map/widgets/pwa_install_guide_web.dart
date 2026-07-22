import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/pwa_install_eligibility.dart';

class PwaInstallGuide extends ConsumerStatefulWidget {
  const PwaInstallGuide({super.key});

  @override
  ConsumerState<PwaInstallGuide> createState() => _PwaInstallGuideState();
}

class _PwaInstallGuideState extends ConsumerState<PwaInstallGuide> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _isVisible = isIosPwaEligible();
  }

  void _dismiss() {
    dismissIosPwaGuide();
    setState(() => _isVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final s = ref.watch(l10nProvider);

    return Positioned(
      left: 16,
      right: 16,
      bottom: 100,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.install_mobile, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.pwaInstallTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _StepRow(
                icon: Icons.ios_share,
                text: s.pwaInstallStep1,
              ),
              const SizedBox(height: 12),
              _StepRow(
                icon: Icons.add_box_outlined,
                text: s.pwaInstallStep2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _dismiss,
                  child: Text(s.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
