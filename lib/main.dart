import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // MapKit API key is set via AndroidManifest.xml meta-data and ios/Runner/Info.plist
  runApp(const ProviderScope(child: ParkTrackApp()));
}

class ParkTrackApp extends ConsumerWidget {
  const ParkTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ParkTrack',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU'), Locale('en')],
    );
  }
}
