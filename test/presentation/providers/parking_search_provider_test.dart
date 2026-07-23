import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/models/route_result.dart';
import 'package:mobile/presentation/providers/parking_search_provider.dart';

RouteCandidate _candidate(int zoneId) => RouteCandidate(
  zoneId: zoneId,
  rank: zoneId,
  freeCount: 3,
  confidence: 0.8,
  pay: 0,
);

void main() {
  test(
    'opens the panel after backend results without changing their order',
    () {
      final notifier = ParkingSearchNotifier();
      final candidates = [_candidate(8), _candidate(3), _candidate(5)];

      notifier.startSearch();
      expect(notifier.state.view, ParkingSearchView.loading);

      notifier.showResults(candidates);

      expect(notifier.state.view, ParkingSearchView.results);
      expect(notifier.state.candidates.map((candidate) => candidate.zoneId), [
        8,
        3,
        5,
      ]);
    },
  );

  test('keeps result selection, last viewed item, and scroll position', () {
    final notifier = ParkingSearchNotifier();
    final candidates = [_candidate(1), _candidate(2)];

    notifier.showResults(candidates);
    notifier.saveScrollOffset(86);
    expect(notifier.showDetails(2), isTrue);

    expect(notifier.state.view, ParkingSearchView.details);
    expect(notifier.state.selectedZoneId, 2);
    expect(notifier.state.lastViewedZoneId, 2);

    notifier.backToResults();

    expect(notifier.state.view, ParkingSearchView.results);
    expect(notifier.state.selectedZoneId, isNull);
    expect(notifier.state.lastViewedZoneId, 2);
    expect(notifier.state.scrollOffset, 86);

    notifier.showResults(candidates);
    expect(notifier.state.scrollOffset, 86);
    expect(notifier.state.lastViewedZoneId, 2);
  });

  test('resets presentation state for a different result set', () {
    final notifier = ParkingSearchNotifier();
    notifier.showResults([_candidate(1)]);
    notifier.saveScrollOffset(100);
    notifier.showDetails(1);

    notifier.showResults([_candidate(3)]);

    expect(notifier.state.resultZoneIds, {3});
    expect(notifier.state.scrollOffset, 0);
    expect(notifier.state.lastViewedZoneId, isNull);
  });

  test('resets previous results and selection when a new search starts', () {
    final notifier = ParkingSearchNotifier();
    notifier.showResults([_candidate(1), _candidate(2)]);
    notifier.showDetails(2);
    notifier.saveScrollOffset(80);

    notifier.startSearch();

    expect(notifier.state.view, ParkingSearchView.loading);
    expect(notifier.state.candidates, isEmpty);
    expect(notifier.state.selectedZoneId, isNull);
    expect(notifier.state.lastViewedZoneId, isNull);
    expect(notifier.state.scrollOffset, 0);
  });

  test('accepts only a result as the selected parking', () {
    final notifier = ParkingSearchNotifier();
    notifier.showResults([_candidate(5)]);

    expect(notifier.showDetails(9), isFalse);
    expect(notifier.state.selectedZoneId, isNull);

    notifier.startRoute(5);
    expect(notifier.state.view, ParkingSearchView.hidden);
    expect(notifier.state.selectedZoneId, 5);

    notifier.clear();
    expect(notifier.state.candidates, isEmpty);
    expect(notifier.state.view, ParkingSearchView.hidden);
  });

  test('list and marker selection produce the same result state', () {
    final listSelection = ParkingSearchNotifier()
      ..showResults([_candidate(5), _candidate(7)])
      ..showDetails(7);
    final markerSelection = ParkingSearchNotifier()
      ..showResults([_candidate(5), _candidate(7)])
      ..showDetails(7);

    expect(markerSelection.state.view, listSelection.state.view);
    expect(
      markerSelection.state.selectedZoneId,
      listSelection.state.selectedZoneId,
    );
    expect(
      markerSelection.state.lastViewedZoneId,
      listSelection.state.lastViewedZoneId,
    );
    expect(
      markerSelection.state.candidates.map((candidate) => candidate.zoneId),
      listSelection.state.candidates.map((candidate) => candidate.zoneId),
    );
  });

  test('route failure returns to results without losing candidates', () {
    final notifier = ParkingSearchNotifier();
    final candidates = [_candidate(2), _candidate(4)];
    notifier.showResults(candidates);
    notifier.startRoute(4);

    notifier.backToResults();

    expect(notifier.state.view, ParkingSearchView.results);
    expect(notifier.state.lastViewedZoneId, 4);
    expect(notifier.state.candidates.map((candidate) => candidate.zoneId), [
      2,
      4,
    ]);
  });
}
