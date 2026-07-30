import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/domain/models/route_result.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/screens/map/widgets/parking_card_sheet.dart';

void main() {
  testWidgets('selected result card stays non-modal and exposes navigation', (
    tester,
  ) async {
    var back = false;
    var previous = false;
    var next = false;
    var route = false;
    var external = false;
    var shared = false;
    const zone = Zone(
      zoneId: 42,
      zoneType: ZoneType.standard,
      capacity: 10,
      freeCount: 5,
      confidence: 0.9,
      pay: 60,
      geometry: [],
      isPrivate: true,
      isAccessible: true,
    );
    const candidate = RouteCandidate(
      zoneId: 42,
      rank: 2,
      freeCount: 5,
      confidence: 0.9,
      pay: 60,
      durationFromOriginSeconds: 360,
      predictedFreeCount: 4,
      eta: '2026-07-23T13:23:00+03:00',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [l10nProvider.overrideWithValue(AppStrings.en)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 410,
                child: ParkingCardSheet(
                  zone: zone,
                  candidate: candidate,
                  resultIndex: 1,
                  resultCount: 3,
                  onBack: () => back = true,
                  onPrevious: () => previous = true,
                  onNext: () => next = true,
                  onBuildRoute: () => route = true,
                  onOpenExternal: () => external = true,
                  onShare: (_) => shared = true,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Parking #42'), findsOneWidget);
    expect(find.text('5 spaces'), findsOneWidget);
    expect(find.text('/ 10'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Accessible parking'), findsOneWidget);
    expect(find.text('Confidence: 90%'), findsOneWidget);
    expect(find.text('4 spaces by 13:23'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ParkingCardSheet),
        matching: find.byType(ModalBarrier),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Back to results'));
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.ensureVisible(find.text('Route'));
    await tester.tap(find.text('Route'));
    await tester.ensureVisible(find.text('Yandex Maps'));
    await tester.tap(find.text('Yandex Maps'));
    await tester.tap(find.byKey(const Key('parking_share')));

    expect(back, isTrue);
    expect(previous, isTrue);
    expect(next, isTrue);
    expect(route, isTrue);
    expect(external, isTrue);
    expect(shared, isTrue);
    expect(tester.takeException(), isNull);
  });
}
