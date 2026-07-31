import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/domain/models/route_result.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/providers/time_selector_provider.dart';
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
    expect(find.textContaining('from you'), findsOneWidget);
    final predictedFinder = find.byKey(
      const Key('parking_details_predicted_42'),
    );
    final predictedBadge = tester.widget<Container>(
      find.descendant(of: predictedFinder, matching: find.byType(Container)),
    );
    final predictedDecoration = predictedBadge.decoration! as BoxDecoration;
    expect(predictedDecoration.color, Colors.transparent);
    expect(predictedDecoration.border!.top.color, const Color(0xFF2E7D32));
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: predictedFinder, matching: find.byType(Icon)),
          )
          .color,
      const Color(0xFF2E7D32),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: predictedFinder, matching: find.byType(Text)),
          )
          .style
          ?.color,
      const Color(0xFF2E7D32),
    );
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

  testWidgets('shows occupancy update time for current data', (tester) async {
    final updatedAt = DateTime.now().subtract(const Duration(minutes: 5));
    final zone = _zone(occupancyUpdatedAt: updatedAt);

    await _pumpCard(tester, zone: zone);

    expect(
      find.byKey(const Key('parking_occupancy_updated_at')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Updated: ${formatParkingCardDateTime(updatedAt, AppStrings.en)}',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('parking_forecast_for')), findsNothing);
  });

  testWidgets('shows past update no later than selected time', (tester) async {
    final selectedAt = DateTime(2042, 5, 10, 15);
    final updatedAt = DateTime(2042, 5, 10, 14, 30);
    final notifier = TimeSelectorNotifier()..setPast(selectedAt);

    await _pumpCard(
      tester,
      zone: _zone(occupancyUpdatedAt: updatedAt),
      timeNotifier: notifier,
    );

    expect(find.text('Updated: 10 May 2042, 14:30'), findsOneWidget);
    expect(updatedAt.isAfter(selectedAt), isFalse);
  });

  testWidgets('hides an invalid past update later than selected time', (
    tester,
  ) async {
    final notifier = TimeSelectorNotifier()..setPast(DateTime(2042, 5, 10, 15));

    await _pumpCard(
      tester,
      zone: _zone(occupancyUpdatedAt: DateTime(2042, 5, 10, 15, 1)),
      timeNotifier: notifier,
    );

    expect(find.byKey(const Key('parking_occupancy_updated_at')), findsNothing);
  });

  testWidgets('shows forecast metadata and warns at exactly 30 minutes', (
    tester,
  ) async {
    final selectedAt = DateTime(2042, 5, 10, 15);
    final forecastFor = DateTime(2042, 5, 10, 14, 30);
    final generatedAt = DateTime(2042, 5, 9, 22, 15);
    final notifier = TimeSelectorNotifier()..setFuture(selectedAt);

    await _pumpCard(
      tester,
      zone: _zone(
        occupancyUpdatedAt: DateTime(2042, 5, 10, 12),
        forecastFor: forecastFor,
        forecastGeneratedAt: generatedAt,
      ),
      timeNotifier: notifier,
    );

    expect(find.text('Forecast for: 10 May 2042, 14:30'), findsOneWidget);
    expect(find.text('Generated: 9 May 2042, 22:15'), findsOneWidget);
    expect(find.byKey(const Key('parking_occupancy_updated_at')), findsNothing);
    expect(
      find.text(
        'Forecast for 10 May 2042, 14:30, '
        'you picked 10 May 2042, 15:00',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('parking_forecast_mismatch_warning')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('parking_open_closest_forecast')),
    );
    await tester.tap(find.byKey(const Key('parking_open_closest_forecast')));
    await tester.pump();

    expect(
      notifier.state.maybeWhen(future: (at) => at, orElse: () => null),
      forecastFor,
    );
    expect(
      find.byKey(const Key('parking_forecast_mismatch_warning')),
      findsNothing,
    );
  });

  testWidgets('does not warn when forecast differs by under 30 minutes', (
    tester,
  ) async {
    final selectedAt = DateTime(2042, 5, 10, 15);
    final notifier = TimeSelectorNotifier()..setFuture(selectedAt);

    await _pumpCard(
      tester,
      zone: _zone(
        forecastFor: selectedAt.subtract(const Duration(minutes: 29)),
        forecastGeneratedAt: DateTime(2042, 5, 10, 12),
      ),
      timeNotifier: notifier,
    );

    expect(find.byKey(const Key('parking_forecast_for')), findsOneWidget);
    expect(
      find.byKey(const Key('parking_forecast_mismatch_warning')),
      findsNothing,
    );
  });
}

Zone _zone({
  DateTime? occupancyUpdatedAt,
  DateTime? forecastFor,
  DateTime? forecastGeneratedAt,
}) => Zone(
  zoneId: 42,
  zoneType: ZoneType.standard,
  capacity: 10,
  freeCount: 5,
  confidence: 0.9,
  pay: 0,
  geometry: const [],
  occupancyUpdatedAt: occupancyUpdatedAt,
  forecastFor: forecastFor,
  forecastGeneratedAt: forecastGeneratedAt,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required Zone zone,
  TimeSelectorNotifier? timeNotifier,
}) async {
  final notifier = timeNotifier ?? TimeSelectorNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        l10nProvider.overrideWithValue(AppStrings.en),
        timeSelectorProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 700,
              child: ParkingCardSheet(
                zone: zone,
                onBuildRoute: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
