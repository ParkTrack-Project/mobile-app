import '../localization/app_localizations.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  factory ApiException.fromStatusCode(int code) {
    // We return a technical message by default, but it will be localized in UI
    return switch (code) {
      401 => ApiException('Unauthorized', statusCode: 401),
      403 => ApiException('Forbidden', statusCode: 403),
      404 => ApiException('Not Found', statusCode: 404),
      409 => ApiException('Conflict', statusCode: 409),
      422 => ApiException('Invalid Data', statusCode: 422),
      500 => ApiException('Server Error', statusCode: 500),
      _ => ApiException('Request Error ($code)', statusCode: code),
    };
  }

  String getLocalizedMessage(AppStrings s) {
    return switch (statusCode) {
      401 => s.unauthorized,
      403 => s.forbidden,
      404 => s.notFound,
      409 => s.emailAlreadyExists,
      422 => s.invalidData,
      500 => s.serverError,
      _ => '${s.requestError} ($statusCode)',
    };
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
