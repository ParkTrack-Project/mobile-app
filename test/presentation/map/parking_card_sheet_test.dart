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
    const zone = Zone(
      zoneId: 42,
      zoneType: ZoneType.standard,
      capacity: 10,
      freeCount: 5,
      confidence: 0.9,
      pay: 60,
      geometry: [],
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
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Parking #42'), findsWidgets);
    expect(find.text('4 spaces by 13:23'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ParkingCardSheet),
        matching: find.byType(ModalBarrier),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Back to results'));
    await tester.ensureVisible(find.text('Previous parking'));
    await tester.tap(find.text('Previous parking'));
    await tester.ensureVisible(find.text('Next parking'));
    await tester.tap(find.text('Next parking'));
    await tester.ensureVisible(find.text('Build Route'));
    await tester.tap(find.text('Build Route'));

    expect(back, isTrue);
    expect(previous, isTrue);
    expect(next, isTrue);
    expect(route, isTrue);
    expect(tester.takeException(), isNull);
  });
}
