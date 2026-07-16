import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';
import 'mock_interceptor.dart';

Dio createDio(TokenStorage tokenStorage) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  final interceptors = <Interceptor>[];
  if (kUseMocks) {
    interceptors.add(MockInterceptor());
  }
  interceptors.add(AuthInterceptor(tokenStorage, dio));
  if (kDebugMode) {
    interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: false,
      ),
    );
  }
  dio.interceptors.addAll(interceptors);

  return dio;
}
