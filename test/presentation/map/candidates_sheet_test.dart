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
      eta: '2026-07-23T12:01:00+03:00',
      routePolyline: const [
        Point(latitude: 61.789, longitude: 34.359),
        Point(latitude: 61.790, longitude: 34.359),
      ],
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
          parkingAddressProvider.overrideWith((_, _) async => '42 Test Street'),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: CandidatesSheet(
                candidates: [candidate],
                zones: [zone],
                hasDestination: true,
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
    expect(find.text('Ranked by time and distance'), findsOneWidget);
    expect(find.text('42 Test Street'), findsOneWidget);
    expect(find.text('Parking #42'), findsOneWidget);
    expect(find.text('450 m'), findsOneWidget);
    expect(find.textContaining('111 m (6 min) from you'), findsOneWidget);
    expect(find.text('Forecast: 5 spaces by 12:01'), findsOneWidget);
    expect(find.text('7 spaces'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Accessible parking'), findsOneWidget);

    await tester.tap(find.byKey(const Key('parking_candidate_42')));
    expect(selectedZoneId, 42);

    expect(find.byKey(const Key('parking_candidate_go_42')), findsOneWidget);
    expect(
      find.byKey(const Key('parking_candidate_yandex_42')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('parking_candidate_go_42')));
    await tester.pumpAndSettle();
    expect(selectedAction, CandidateAction.go);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel can collapse and expand without replacing results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final heights = <double>[];
    final candidate = RouteCandidate(
      zoneId: 1,
      rank: 1,
      freeCount: 3,
      confidence: 0.8,
      pay: 0,
      durationFromOriginSeconds: 300,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [l10nProvider.overrideWithValue(AppStrings.en)],
        child: MaterialApp(
          home: Scaffold(
            body: CandidatesSheet(
              candidates: [candidate],
              zones: const [],
              lastViewedZoneId: null,
              initialScrollOffset: 0,
              onSelect: (_) {},
              onAction: (_, _, _) {},
              onPanelHeightChanged: heights.add,
              onScrollOffsetChanged: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final initialHeight = heights.last;

    await tester.drag(
      find.byKey(const Key('parking_results_drag_handle')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(heights.last, lessThan(initialHeight));
    expect(find.byKey(const Key('parking_candidate_1')), findsOneWidget);
  });

  testWidgets('renders explicit loading, empty, and error states', (
    tester,
  ) async {
    Future<void> pump(ParkingResultsPanelState state) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [l10nProvider.overrideWithValue(AppStrings.en)],
          child: MaterialApp(
            home: SizedBox(
              height: 420,
              child: CandidatesSheet(
                candidates: const [],
                zones: const [],
                lastViewedZoneId: null,
                initialScrollOffset: 0,
                panelState: state,
                onSelect: (_) {},
                onAction: (_, _, _) {},
                onScrollOffsetChanged: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
    }

    await pump(ParkingResultsPanelState.loading);
    expect(find.byKey(const Key('parking_search_loading')), findsOneWidget);

    await pump(ParkingResultsPanelState.results);
    expect(find.byKey(const Key('parking_search_empty')), findsOneWidget);

    await pump(ParkingResultsPanelState.error);
    expect(find.byKey(const Key('parking_search_error')), findsOneWidget);
  });
}
