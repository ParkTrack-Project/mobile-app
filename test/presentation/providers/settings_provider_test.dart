import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/settings_storage.dart';
import 'package:mobile/presentation/providers/settings_provider.dart';

class _DelayedSettingsStorage extends SettingsStorage {
  final saveCompleter = Completer<void>();
  String? savedLanguage;

  @override
  Future<ThemeMode> getThemeMode() async => ThemeMode.system;

  @override
  Future<String?> getLanguage() async => null;

  @override
  Future<void> saveLanguage(String? languageCode) async {
    savedLanguage = languageCode;
    await saveCompleter.future;
  }
}

void main() {
  test('updates locale before persistence completes', () async {
    final storage = _DelayedSettingsStorage();
    final notifier = SettingsNotifier(storage);
    await Future<void>.delayed(Duration.zero);

    final pendingSave = notifier.setLanguage('en');

    expect(notifier.state.locale, const Locale('en'));
    expect(storage.savedLanguage, 'en');
    storage.saveCompleter.complete();
    await pendingSave;
    notifier.dispose();
  });
}
