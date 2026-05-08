class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  factory ApiException.fromStatusCode(int code) {
    return switch (code) {
      401 => const ApiException('Не авторизован', statusCode: 401),
      403 => const ApiException('Нет доступа', statusCode: 403),
      404 => const ApiException('Не найдено', statusCode: 404),
      409 => const ApiException('Пользователь с таким email уже существует', statusCode: 409),
      422 => const ApiException('Неверные данные', statusCode: 422),
      500 => const ApiException('Ошибка сервера', statusCode: 500),
      _ => ApiException('Ошибка запроса ($code)', statusCode: code),
    };
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
