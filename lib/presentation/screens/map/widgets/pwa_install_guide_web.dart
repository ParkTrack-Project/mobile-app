import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/pwa_install_eligibility.dart';

@JS('navigator.standalone')
external JSBoolean? get _navigatorStandalone;

class PwaInstallGuide extends ConsumerStatefulWidget {
  const PwaInstallGuide({super.key});

  @override
  ConsumerState<PwaInstallGuide> createState() => _PwaInstallGuideState();
}

class _PwaInstallGuideState extends ConsumerState<PwaInstallGuide> {
  static const _storageKey = 'parktrack.pwa.install-guide';
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _isVisible = _isEligible();
  }

  bool _isEligible() {
    String? dismissedVersion;
    try {
      dismissedVersion = web.window.localStorage.getItem(_storageKey);
    } catch (_) {
      dismissedVersion = null;
    }
    return shouldShowPwaInstallGuide(
      isWeb: true,
      userAgent: web.window.navigator.userAgent,
      platform: web.window.navigator.platform,
      maxTouchPoints: web.window.navigator.maxTouchPoints,
      navigatorStandalone: _navigatorStandalone?.toDart ?? false,
      displayModeStandalone: web.window
          .matchMedia('(display-mode: standalone)')
          .matches,
      dismissedVersion: dismissedVersion,
    );
  }

  void _dismiss() {
    try {
      web.window.localStorage.setItem(_storageKey, pwaInstallGuideVersion);
    } catch (_) {
      // The in-memory state still prevents repeats during this app session.
    }
    setState(() => _isVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();
    final strings = ref.watch(l10nProvider);
    final colors = Theme.of(context).colorScheme;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Material(
        elevation: 10,
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.install_mobile, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.installPwa,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InstallStep(icon: Icons.ios_share, text: strings.pwaStep1),
              const SizedBox(height: 10),
              _InstallStep(
                icon: Icons.add_box_outlined,
                text: strings.pwaStep2,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _dismiss,
                  child: Text(strings.ok),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallStep extends StatelessWidget {
  const _InstallStep({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}
