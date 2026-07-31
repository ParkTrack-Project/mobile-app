import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/settings_storage.dart';
import 'package:mobile/presentation/providers/app_version_provider.dart';
import 'package:mobile/presentation/providers/settings_provider.dart';
import 'package:mobile/presentation/screens/profile/profile_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _TestSettingsStorage extends SettingsStorage {
  @override
  Future<ThemeMode> getThemeMode() async => ThemeMode.system;

  @override
  Future<String?> getLanguage() async => 'ru';
}

void main() {
  test(
    'reads and formats the application version from package metadata',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'ParkTrack',
        packageName: 'com.parktrack.mobile',
        version: '1.4.0',
        buildNumber: '4',
        buildSignature: '',
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final appVersion = await container.read(appVersionProvider.future);

      expect(appVersion.version, '1.4.0');
      expect(appVersion.buildNumber, '4');
      expect(appVersion.label, 'ParkTrack v1.4.0+4');
    },
  );

  testWidgets('shows the version supplied by appVersionProvider', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStorageProvider.overrideWithValue(_TestSettingsStorage()),
          appVersionProvider.overrideWith(
            (ref) async =>
                const AppVersion(version: '9.8.7', buildNumber: '654'),
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ParkTrack v9.8.7+654'), findsOneWidget);
    expect(find.text('ParkTrack v1.3.0+3'), findsNothing);
  });
}
