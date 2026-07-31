import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/settings_storage.dart';
import 'package:mobile/presentation/providers/settings_provider.dart';
import 'package:mobile/presentation/screens/auth/login_screen.dart';
import 'package:mobile/presentation/screens/auth/register_screen.dart';
import 'package:mobile/presentation/screens/auth/widgets/language_switcher.dart';

class _MemorySettingsStorage extends SettingsStorage {
  String? language;

  @override
  Future<ThemeMode> getThemeMode() async => ThemeMode.system;

  @override
  Future<String?> getLanguage() async => language;

  @override
  Future<void> saveLanguage(String? languageCode) async {
    language = languageCode;
  }
}

void main() {
  testWidgets('login page shows only the app bar language switcher', (
    tester,
  ) async {
    final storage = _MemorySettingsStorage()..language = 'ru';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStorageProvider.overrideWithValue(storage)],
        child: const _LoginTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LanguageSwitcher), findsOneWidget);
  });

  testWidgets('switches language before authentication without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _MemorySettingsStorage()..language = 'ru';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStorageProvider.overrideWithValue(storage)],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();

    expect(storage.language, 'en');
    expect(find.text('Registration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LoginTestApp extends ConsumerWidget {
  const _LoginTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      locale: settings.locale,
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginScreen(),
    );
  }
}

class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      locale: settings.locale,
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RegisterScreen(),
    );
  }
}
