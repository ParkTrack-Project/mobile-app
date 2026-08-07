import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/presentation/providers/app_providers.dart';

class _DelayedTokenStorage extends TokenStorage {
  final result = Completer<bool>();

  @override
  Future<bool> hasToken() => result.future;
}

void main() {
  test('creates a destination from valid deep-link coordinates', () {
    final destination = destinationFromDeepLink(
      Uri.parse('/destination?lat=61.789114&lon=34.359757&name=Station'),
    );

    expect(destination?.latitude, 61.789114);
    expect(destination?.longitude, 34.359757);
    expect(destination?.name, 'Station');
  });

  test('rejects invalid destination coordinates', () {
    expect(
      destinationFromDeepLink(Uri.parse('/destination?lat=100&lon=34.359757')),
      isNull,
    );
  });

  testWidgets('keeps the router and deep link while auth state resolves', (
    tester,
  ) async {
    final tokenStorage = _DelayedTokenStorage();
    final container = ProviderContainer(
      overrides: [tokenStorageProvider.overrideWithValue(tokenStorage)],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    router.go('/parking/42');
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/?from=%2Fparking%2F42',
    );

    tokenStorage.result.complete(false);
    await tester.pump();
    await tester.pump();

    expect(container.read(routerProvider), same(router));
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/login?from=%2Fparking%2F42',
    );
  });
}
