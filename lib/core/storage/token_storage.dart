import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _keyAccess = 'access_token';
  static const _keyLogin = 'user_login';
  static const _keyPassword = 'user_password';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccess, value: token);

  Future<String?> getAccessToken() => _storage.read(key: _keyAccess);

  Future<void> saveCredentials(String login, String password) async {
    await _storage.write(key: _keyLogin, value: login);
    await _storage.write(key: _keyPassword, value: password);
    print("Credentials saved.");
  }

  Future<String?> getLogin() => _storage.read(key: _keyLogin);
  Future<String?> getPassword() => _storage.read(key: _keyPassword);

  Future<void> clearAll() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyLogin);
    await _storage.delete(key: _keyPassword);
  }

  Future<void> clearTokens() => _storage.delete(key: _keyAccess);

  Future<bool> hasToken() async => (await getAccessToken()) != null;
}
