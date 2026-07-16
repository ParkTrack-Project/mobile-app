import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsStorage {
  static const _keyTheme = 'app_theme';
  static const _keyLanguage = 'app_language';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveThemeMode(ThemeMode mode) =>
      _storage.write(key: _keyTheme, value: mode.name);

  Future<ThemeMode> getThemeMode() async {
    final value = await _storage.read(key: _keyTheme);
    return ThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveLanguage(String? languageCode) async {
    if (languageCode == null) {
      await _storage.delete(key: _keyLanguage);
    } else {
      await _storage.write(key: _keyLanguage, value: languageCode);
    }
  }

  Future<String?> getLanguage() => _storage.read(key: _keyLanguage);
}
