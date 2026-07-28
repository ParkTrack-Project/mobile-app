import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/presentation/providers/navigation_provider.dart';
import 'package:mobile/presentation/screens/map/widgets/navigation_overlay.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  testWidgets('bottom bar shows icons for all navigation stats', (
    tester,
  ) async {
    await _pumpBottomBar(
      tester,
      const NavigationData(
        zoneId: 1,
        route: [],
        remainingMeters: 1600,
        remainingSeconds: 900,
        speedKmh: 40,
        currentPosition: Point(latitude: 0, longitude: 0),
        heading: 0,
      ),
    );

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    expect(find.text('1,6 км'), findsOneWidget);
  });

  testWidgets('speed icon and value become red above 90 km/h', (tester) async {
    await _pumpBottomBar(
      tester,
      const NavigationData(
        zoneId: 1,
        route: [],
        remainingMeters: 1600,
        remainingSeconds: 900,
        speedKmh: 91,
        currentPosition: Point(latitude: 0, longitude: 0),
        heading: 0,
      ),
    );

    final speedIcon = tester.widget<Icon>(find.byIcon(Icons.speed_rounded));
    final speedText = tester.widget<Text>(find.text('91 км/ч'));

    expect(speedIcon.color, Colors.red.shade600);
    expect(speedText.style?.color, Colors.red.shade600);
  });
}

Future<void> _pumpBottomBar(WidgetTester tester, NavigationData data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        l10nProvider.overrideWithValue(AppStrings.ru),
        navigationProvider.overrideWith(() => _TestNavigationNotifier(data)),
      ],
      child: MaterialApp(
        home: Scaffold(body: NavigationBottomBar(onFinish: () {})),
      ),
    ),
  );
}

class _TestNavigationNotifier extends NavigationNotifier {
  _TestNavigationNotifier(this.data);

  final NavigationData data;

  @override
  NavigationData? build() => data;
}
