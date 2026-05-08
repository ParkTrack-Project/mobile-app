import 'package:dio/dio.dart';
import '../api/auth_api.dart';
import '../models/auth_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/token_storage.dart';
import '../../domain/models/user.dart';

class AuthRepository {
  final AuthApi _api;
  final TokenStorage _tokenStorage;

  AuthRepository(this._api, this._tokenStorage);

  Future<User> login(String login, String password) async {
    try {
      final response = await _api.login(LoginRequestDto(login: login, password: password));
      await _tokenStorage.saveAccessToken(response.accessToken);
      return _mapUser(response.user);
    } on DioException catch (e) {
      throw ApiException.fromStatusCode(e.response?.statusCode ?? 0);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Ошибка: $e');
    }
  }

  Future<User> register(String email, String password, {String? fullName}) async {
    try {
      final response = await _api.register(
        RegisterRequestDto(email: email, password: password, fullName: fullName),
      );
      await _tokenStorage.saveAccessToken(response.accessToken);
      return _mapUser(response.user);
    } on DioException catch (e) {
      throw ApiException.fromStatusCode(e.response?.statusCode ?? 0);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Ошибка: $e');
    }
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      await _tokenStorage.clearTokens();
    }
  }

  Future<User?> getMe() async {
    try {
      final dto = await _api.getMe();
      return _mapUser(dto);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      return null;
    }
  }

  User _mapUser(UserDto dto) => User(
        userId: dto.userId,
        email: dto.email,
        fullName: dto.fullName,
        roles: dto.globalRole != null ? [dto.globalRole!] : [],
      );
}
