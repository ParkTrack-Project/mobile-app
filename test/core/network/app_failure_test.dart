import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/core/network/api_exception.dart';

void main() {
  final request = RequestOptions(path: '/test');

  test('classifies transport and timeout errors', () {
    expect(
      AppFailure.from(const SocketException('offline')).kind,
      AppFailureKind.noInternet,
    );
    expect(
      AppFailure.from(TimeoutException('late')).kind,
      AppFailureKind.timeout,
    );
    expect(
      AppFailure.from(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionTimeout,
        ),
      ).kind,
      AppFailureKind.timeout,
    );
  });

  test('classifies HTTP failures without exposing the response body', () {
    final unavailable = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<void>(requestOptions: request, statusCode: 503),
    );
    final server = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<void>(requestOptions: request, statusCode: 502),
    );

    expect(
      AppFailure.from(unavailable).kind,
      AppFailureKind.serviceUnavailable,
    );
    expect(AppFailure.from(server).kind, AppFailureKind.server);
  });

  test('classifies location platform failures', () {
    expect(
      AppFailure.from(const LocationServiceDisabledException()).kind,
      AppFailureKind.locationServicesDisabled,
    );
    expect(
      AppFailure.from(const PermissionDeniedException('denied')).kind,
      AppFailureKind.locationPermissionDenied,
    );
    expect(
      AppFailure.from(PlatformException(code: 'PERMISSION_DENIED')).kind,
      AppFailureKind.locationPermissionDenied,
    );
  });

  test('uses a safe caller-provided fallback for unknown errors', () {
    expect(
      AppFailure.from(
        StateError('technical detail'),
        fallback: AppFailureKind.routeLoad,
      ).kind,
      AppFailureKind.routeLoad,
    );
  });
}
