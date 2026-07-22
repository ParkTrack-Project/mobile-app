import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../network/api_exception.dart';

class ErrorMessageDeduplicator {
  ErrorMessageDeduplicator({this.interval = const Duration(seconds: 5)});

  final Duration interval;
  String? _lastMessage;
  DateTime? _lastShownAt;

  bool shouldShow(String message, DateTime now) {
    final duplicate =
        _lastMessage == message &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < interval;
    if (duplicate) return false;
    _lastMessage = message;
    _lastShownAt = now;
    return true;
  }
}

final _errorDeduplicator = ErrorMessageDeduplicator();

void showErrorSnackBar(
  BuildContext context,
  String fallbackMessage, {
  Object? error,
  StackTrace? stackTrace,
  AppStrings? s,
  VoidCallback? onRetry,
  AppFailureKind failureFallback = AppFailureKind.unknown,
}) {
  final failure = error == null
      ? null
      : AppFailure.from(error, fallback: failureFallback);
  final message = failure != null && s != null
      ? failure.localizedMessage(s)
      : fallbackMessage;

  if (!_errorDeduplicator.shouldShow(message, DateTime.now())) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      action: onRetry == null
          ? null
          : SnackBarAction(label: s?.retry ?? 'Retry', onPressed: onRetry),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ),
  );
}
