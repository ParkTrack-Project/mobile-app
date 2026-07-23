import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/browser_locale.dart';
import '../../core/storage/settings_storage.dart';

class SettingsState {
  final ThemeMode themeMode;
  final Locale? locale;

  SettingsState({required this.themeMode, this.locale});

  SettingsState copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool clearLocale = false,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      locale: clearLocale ? null : (locale ?? this.locale),
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsStorage _storage;
  static const _channel = MethodChannel('com.parktrack.mobile/mapkit');
  int _languageGeneration = 0;

  SettingsNotifier(this._storage)
    : super(SettingsState(themeMode: ThemeMode.system)) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final languageGeneration = _languageGeneration;
    final themeFuture = _storage.getThemeMode();
    final languageFuture = _storage.getLanguage();
    final theme = await themeFuture;
    String? lang = await languageFuture;

    if (lang == null) {
      final browserLang = detectBrowserLanguage();
      if (browserLang != null) {
        if (browserLang.startsWith('ru')) {
          lang = 'ru';
        } else {
          lang = 'en';
        }
      }
    }

    if (languageGeneration != _languageGeneration) {
      state = state.copyWith(themeMode: theme);
      return;
    }
    if (lang != null) {
      _setMapKitLocale(lang);
    }
    state = state.copyWith(
      themeMode: theme,
      locale: lang != null ? Locale(lang) : null,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storage.saveThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLanguage(String? languageCode) async {
    _languageGeneration++;
    state = state.copyWith(
      locale: languageCode != null ? Locale(languageCode) : null,
      clearLocale: languageCode == null,
    );
    await _storage.saveLanguage(languageCode);
    if (languageCode != null) {
      _setMapKitLocale(languageCode);
    }
  }

  Future<void> setLocale(Locale locale) => setLanguage(locale.languageCode);

  Future<void> _setMapKitLocale(String lang) async {
    try {
      // MapKit uses language codes like "ru_RU" or "en_US"
      final mapLocale = lang == 'ru' ? 'ru_RU' : 'en_US';
      await _channel.invokeMethod('setLocale', {'locale': mapLocale});
    } catch (_) {}
  }
}

final settingsStorageProvider = Provider((ref) => SettingsStorage());

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier(ref.watch(settingsStorageProvider));
  },
);
