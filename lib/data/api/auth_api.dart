import 'package:dio/dio.dart';
import '../models/auth_models.dart';

class AuthApi {
  final Dio _dio;

  AuthApi(this._dio);

  Future<AuthResponseDto> register(RegisterRequestDto request) async {
    final response = await _dio.post('/auth/register', data: request.toJson());
    return AuthResponseDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AuthResponseDto> login(LoginRequestDto request) async {
    final response = await _dio.post('/auth/login', data: request.toJson());
    return AuthResponseDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> logout() => _dio.post('/auth/logout');

  Future<UserDto> getMe() async {
    final response = await _dio.get('/auth/me');
    return UserDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> requestPasswordReset(String email) =>
      _dio.post('/auth/password-reset/request', data: {'email': email});
}
