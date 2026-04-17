import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _keyAccess = 'access_token';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccess, value: token);

  Future<String?> getAccessToken() => _storage.read(key: _keyAccess);

  Future<void> clearTokens() => _storage.delete(key: _keyAccess);

  Future<bool> hasToken() async => (await getAccessToken()) != null;
}
