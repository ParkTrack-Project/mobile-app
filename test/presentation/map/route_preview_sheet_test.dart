import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/domain/models/route_result.dart';
import 'package:mobile/presentation/screens/map/widgets/route_preview_sheet.dart';

void main() {
  testWidgets('shows route preview actions without a modal map blocker', (
    tester,
  ) async {
    var goPressed = false;
    var closePressed = false;
    const route = ActiveRoute(
      routeId: 1,
      status: 'ready',
      selectedZoneId: 2,
      routeDistanceMeters: 1400,
      routeDurationSeconds: 360,
      candidates: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [l10nProvider.overrideWithValue(AppStrings.en)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 330,
                child: RoutePreviewSheet(
                  route: route,
                  zoneLat: 61,
                  zoneLon: 34,
                  onNavigateInApp: () => goPressed = true,
                  onClose: () => closePressed = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Route Ready'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Open in Yandex Maps'), findsOneWidget);
    expect(find.text('from you:'), findsOneWidget);
    expect(find.text('1.4 km • 6 min'), findsOneWidget);
    expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RoutePreviewSheet),
        matching: find.byType(ModalBarrier),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Go'));
    expect(goPressed, isTrue);
    await tester.tap(find.text('Reset'));
    expect(closePressed, isTrue);
  });
}
