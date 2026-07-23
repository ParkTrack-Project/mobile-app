import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/router/url_strategy.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/screens/map/widgets/pwa_install_guide.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  // MapKit API key is set via AndroidManifest.xml meta-data and ios/Runner/Info.plist
  runApp(const ProviderScope(child: ParkTrackApp()));
}

class ParkTrackApp extends ConsumerWidget {
  const ParkTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'ParkTrack',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU'), Locale('en')],
      builder: (context, child) => _AppBuilder(child: child),
    );
  }
}

class _AppBuilder extends StatelessWidget {
  const _AppBuilder({this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (child == null) return const SizedBox.shrink();
    return Material(
      child: Stack(
        children: [
          RepaintBoundary(child: child!),
          const PwaInstallGuide(),
        ],
      ),
    );
  }
}
