import 'package:dio/dio.dart';
import '../constants.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';

Dio createDio(TokenStorage tokenStorage) {
  final dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.addAll([
    AuthInterceptor(tokenStorage),
    LogInterceptor(
      requestBody: false,
      responseBody: false,
      requestHeader: false,
    ),
  ]);

  return dio;
}
