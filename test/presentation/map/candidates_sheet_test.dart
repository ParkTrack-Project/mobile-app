import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/domain/models/route_result.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/providers/parking_address_provider.dart';
import 'package:mobile/presentation/screens/map/widgets/candidates_sheet.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  testWidgets('renders actual candidate facts and compact actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selectedZoneId;
    CandidateAction? selectedAction;
    final candidate = RouteCandidate(
      zoneId: 42,
      rank: 1,
      freeCount: 7,
      confidence: 0.9,
      pay: 0,
      distanceToDestinationMeters: 450,
      durationFromOriginSeconds: 360,
      predictedFreeCount: 5,
    );
    final zone = Zone(
      zoneId: 42,
      zoneType: ZoneType.standard,
      capacity: 10,
      freeCount: 7,
      confidence: 0.9,
      pay: 0,
      geometry: const [
        Point(latitude: 1, longitude: 1),
        Point(latitude: 1, longitude: 2),
        Point(latitude: 2, longitude: 2),
      ],
      isAccessible: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          l10nProvider.overrideWithValue(AppStrings.en),
          parkingAddressProvider.overrideWith((_, _) async => '42 Main Street'),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: CandidatesSheet(
                candidates: [candidate],
                zones: [zone],
                lastViewedZoneId: 42,
                initialScrollOffset: 0,
                onSelect: (zoneId) => selectedZoneId = zoneId,
                onAction: (action, _, _) => selectedAction = action,
                onScrollOffsetChanged: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Parking nearby'), findsOneWidget);
    expect(find.text('42 Main Street'), findsOneWidget);
    expect(find.text('7 spaces available'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Accessible parking'), findsOneWidget);

    await tester.tap(find.byKey(const Key('parking_candidate_42')));
    expect(selectedZoneId, 42);

    await tester.tap(find.byKey(const Key('parking_candidate_action_42')));
    await tester.pumpAndSettle();
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Open in Yandex Maps'), findsOneWidget);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(selectedAction, CandidateAction.go);
    expect(tester.takeException(), isNull);
  });
}
