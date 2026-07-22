import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../localization/app_localizations.dart';
import 'network_error_classifier.dart';

enum AppFailureKind {
  noInternet,
  timeout,
  network,
  serviceUnavailable,
  server,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  invalidData,
  locationPermissionDenied,
  locationServicesDisabled,
  mapLoad,
  routeLoad,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, {this.statusCode});

  final AppFailureKind kind;
  final int? statusCode;

  bool get isRecoverable => switch (kind) {
    AppFailureKind.noInternet ||
    AppFailureKind.timeout ||
    AppFailureKind.network ||
    AppFailureKind.serviceUnavailable ||
    AppFailureKind.server ||
    AppFailureKind.mapLoad ||
    AppFailureKind.routeLoad ||
    AppFailureKind.unknown => true,
    _ => false,
  };

  factory AppFailure.from(
    Object error, {
    AppFailureKind fallback = AppFailureKind.unknown,
  }) {
    if (error is AppFailure) return error;
    if (error is ApiException) return error.failure;
    if (error is TimeoutException) {
      return const AppFailure(AppFailureKind.timeout);
    }
    if (isSocketNetworkError(error)) {
      return const AppFailure(AppFailureKind.noInternet);
    }
    if (error is LocationServiceDisabledException) {
      return const AppFailure(AppFailureKind.locationServicesDisabled);
    }
    if (error is PermissionDeniedException) {
      return const AppFailure(AppFailureKind.locationPermissionDenied);
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('permission') || code.contains('denied')) {
        return const AppFailure(AppFailureKind.locationPermissionDenied);
      }
      if (code.contains('location') &&
          (code.contains('disabled') || code.contains('service'))) {
        return const AppFailure(AppFailureKind.locationServicesDisabled);
      }
      if (code.contains('network')) {
        return const AppFailure(AppFailureKind.network);
      }
    }
    if (error is DioException) return _fromDio(error, fallback);
    return AppFailure(fallback);
  }

  static AppFailure _fromDio(DioException error, AppFailureKind fallback) {
    if (error.error != null && isSocketNetworkError(error.error!)) {
      return const AppFailure(AppFailureKind.noInternet);
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AppFailure(AppFailureKind.timeout);
      case DioExceptionType.connectionError:
        return const AppFailure(AppFailureKind.network);
      case DioExceptionType.badResponse:
        return AppFailure.fromStatusCode(error.response?.statusCode ?? 0);
      case DioExceptionType.cancel:
        return AppFailure(fallback);
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return AppFailure(fallback);
    }
  }

  factory AppFailure.fromStatusCode(int code) {
    return switch (code) {
      401 => const AppFailure(AppFailureKind.unauthorized, statusCode: 401),
      403 => const AppFailure(AppFailureKind.forbidden, statusCode: 403),
      404 => const AppFailure(AppFailureKind.notFound, statusCode: 404),
      409 => const AppFailure(AppFailureKind.conflict, statusCode: 409),
      422 => const AppFailure(AppFailureKind.invalidData, statusCode: 422),
      503 => const AppFailure(
        AppFailureKind.serviceUnavailable,
        statusCode: 503,
      ),
      >= 500 => AppFailure(AppFailureKind.server, statusCode: code),
      _ => AppFailure(AppFailureKind.unknown, statusCode: code),
    };
  }

  String localizedMessage(AppStrings strings) => switch (kind) {
    AppFailureKind.noInternet => strings.noInternet,
    AppFailureKind.timeout => strings.requestTimedOut,
    AppFailureKind.network => strings.networkFailure,
    AppFailureKind.serviceUnavailable => strings.serviceUnavailable,
    AppFailureKind.server => strings.serverError,
    AppFailureKind.unauthorized => strings.unauthorized,
    AppFailureKind.forbidden => strings.forbidden,
    AppFailureKind.notFound => strings.notFound,
    AppFailureKind.conflict => strings.emailAlreadyExists,
    AppFailureKind.invalidData => strings.invalidData,
    AppFailureKind.locationPermissionDenied => strings.locationPermissionDenied,
    AppFailureKind.locationServicesDisabled => strings.locationServicesDisabled,
    AppFailureKind.mapLoad => strings.mapLoadError,
    AppFailureKind.routeLoad => strings.routeLoadError,
    AppFailureKind.unknown => strings.unknownError,
  };

  @override
  String toString() => 'AppFailure(${kind.name}, statusCode: $statusCode)';
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, AppFailure? failure})
    : _failure = failure;

  final int? statusCode;
  final String message;
  final AppFailure? _failure;

  AppFailure get failure =>
      _failure ?? AppFailure.fromStatusCode(statusCode ?? 0);

  factory ApiException.fromStatusCode(int code) => ApiException(
    'HTTP $code',
    statusCode: code,
    failure: AppFailure.fromStatusCode(code),
  );

  factory ApiException.fromError(Object error) {
    final failure = AppFailure.from(error);
    return ApiException(
      'Request failed',
      statusCode: failure.statusCode,
      failure: failure,
    );
  }

  String getLocalizedMessage(AppStrings strings) =>
      failure.localizedMessage(strings);

  @override
  String toString() => 'ApiException(statusCode: $statusCode)';
}
