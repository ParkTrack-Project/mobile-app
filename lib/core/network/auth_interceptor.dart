import 'package:dio/dio.dart';
import '../storage/token_storage.dart';
import '../storage/session_expired_notifier.dart';
import '../constants.dart';

class AuthInterceptor extends Interceptor {
  static const _retryKey = 'auth_retry';

  final TokenStorage _tokenStorage;
  final Dio _dio;
  Future<String>? _refreshFuture;
  bool _sessionExpired = false;

  AuthInterceptor(this._tokenStorage, this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401 ||
        err.requestOptions.extra[_retryKey] == true) {
      handler.next(err);
      return;
    }

    try {
      final latestToken = await _tokenStorage.getAccessToken();
      final failedToken = _bearerToken(err.requestOptions);
      final token = latestToken != null && latestToken != failedToken
          ? latestToken
          : await _refreshAccessToken();
      final response = await _retry(err.requestOptions, token);
      handler.resolve(response);
    } catch (_) {
      await _expireSession();
      handler.next(err);
    }
  }

  String? _bearerToken(RequestOptions options) {
    final value = options.headers['Authorization']?.toString();
    return value?.startsWith('Bearer ') == true ? value!.substring(7) : null;
  }

  Future<String> _refreshAccessToken() {
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null) return activeRefresh;

    final refresh = _loginAgain();
    _refreshFuture = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    });
  }

  Future<String> _loginAgain() async {
    final loginFuture = _tokenStorage.getLogin();
    final passwordFuture = _tokenStorage.getPassword();
    final login = await loginFuture;
    final password = await passwordFuture;
    if (login == null || password == null) {
      throw StateError('No credentials available for token refresh');
    }

    final refreshDio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        sendTimeout: _dio.options.sendTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    final response = await refreshDio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login': login, 'password': password},
    );
    final token = response.data?['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Login response does not contain a token');
    }
    await _tokenStorage.saveAccessToken(token);
    _sessionExpired = false;
    return token;
  }

  Future<Response<dynamic>> _retry(
    RequestOptions requestOptions,
    String token,
  ) {
    return _dio.fetch<dynamic>(
      requestOptions.copyWith(
        headers: Map<String, dynamic>.from(requestOptions.headers)
          ..['Authorization'] = 'Bearer $token',
        extra: Map<String, dynamic>.from(requestOptions.extra)
          ..[_retryKey] = true,
      ),
    );
  }

  Future<void> _expireSession() async {
    if (_sessionExpired) return;
    _sessionExpired = true;
    await _tokenStorage.clearAll();
    sessionExpiredNotifier.value = true;
  }
}
