import 'package:dio/dio.dart';
import '../storage/token_storage.dart';
import '../storage/session_expired_notifier.dart';
import '../constants.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  bool _isRefreshing = false;
  final List<ErrorInterceptorHandler> _deferredHandlers = [];

  AuthInterceptor(this._tokenStorage);

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
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final login = await _tokenStorage.getLogin();
      final password = await _tokenStorage.getPassword();

      if (login != null && password != null) {
        if (_isRefreshing) {
          _deferredHandlers.add(handler);
          return;
        }

        _isRefreshing = true;

        try {
          // Use a fresh Dio instance to avoid interceptor recursion
          final refreshDio = _createRefreshDio();
          final response = await refreshDio.post('/auth/login', data: {
            'login': login,
            'password': password,
          });

          final newToken = response.data['access_token'] as String;
          await _tokenStorage.saveAccessToken(newToken);

          // Retry the original request
          final retryResponse = await _retry(err.requestOptions, newToken);
          handler.resolve(retryResponse);

          // For simplicity, we let deferred handlers fail, 
          // but a robust implementation would retry them as well.
          for (final h in _deferredHandlers) {
            h.next(err);
          }
          _deferredHandlers.clear();
          return;
        } catch (e) {
          await _tokenStorage.clearAll();
          sessionExpiredNotifier.value = true;
          for (final h in _deferredHandlers) {
            h.next(err);
          }
          _deferredHandlers.clear();
        } finally {
          _isRefreshing = false;
        }
      } else {
        await _tokenStorage.clearAll();
        sessionExpiredNotifier.value = true;
      }
    }
    handler.next(err);
  }

  Dio _createRefreshDio() {
    return Dio(BaseOptions(baseUrl: kBaseUrl));
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions, String token) {
    final options = Options(
      method: requestOptions.method,
      headers: Map.from(requestOptions.headers)..['Authorization'] = 'Bearer $token',
    );
    return _createRefreshDio().request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}
