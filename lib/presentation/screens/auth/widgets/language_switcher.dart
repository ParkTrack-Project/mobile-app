import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../providers/settings_provider.dart';

class LanguageSwitcher extends ConsumerWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final effectiveLocale = settings.locale ?? Localizations.localeOf(context);
    final selected = effectiveLocale.languageCode == 'en' ? 'en' : 'ru';

    return Semantics(
      label: ref.watch(l10nProvider).language,
      child: SizedBox(
        width: 116,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ru', label: Text('RU')),
            ButtonSegment(value: 'en', label: Text('EN')),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            ref.read(settingsProvider.notifier).setLanguage(selection.first);
          },
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ),
    );
  }
}
