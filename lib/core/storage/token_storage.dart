import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _keyAccess = 'access_token';
  static const _keyLogin = 'user_login';
  static const _keyPassword = 'user_password';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  String? _cachedAccessToken;
  bool _accessTokenLoaded = false;
  Future<String?>? _accessTokenLoad;
  int _accessTokenRevision = 0;

  Future<void> saveAccessToken(String token) async {
    _accessTokenRevision++;
    _cachedAccessToken = token;
    _accessTokenLoaded = true;
    await _storage.write(key: _keyAccess, value: token);
  }

  Future<String?> getAccessToken() {
    if (_accessTokenLoaded) return Future.value(_cachedAccessToken);
    return _accessTokenLoad ??= _loadAccessToken(_accessTokenRevision);
  }

  Future<String?> _loadAccessToken(int revision) async {
    try {
      final storedToken = await _storage.read(key: _keyAccess);
      if (revision == _accessTokenRevision) {
        _cachedAccessToken = storedToken;
        _accessTokenLoaded = true;
      }
      return _cachedAccessToken;
    } finally {
      _accessTokenLoad = null;
    }
  }

  Future<void> saveCredentials(String login, String password) async {
    await _storage.write(key: _keyLogin, value: login);
    await _storage.write(key: _keyPassword, value: password);
  }

  Future<String?> getLogin() => _storage.read(key: _keyLogin);
  Future<String?> getPassword() => _storage.read(key: _keyPassword);

  Future<void> clearAll() async {
    _accessTokenRevision++;
    _cachedAccessToken = null;
    _accessTokenLoaded = true;
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyLogin);
    await _storage.delete(key: _keyPassword);
  }

  Future<void> clearTokens() async {
    _accessTokenRevision++;
    _cachedAccessToken = null;
    _accessTokenLoaded = true;
    await _storage.delete(key: _keyAccess);
  }

  Future<bool> hasToken() async => (await getAccessToken()) != null;
}
