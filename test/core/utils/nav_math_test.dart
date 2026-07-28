import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/core/utils/nav_math.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  group('formatNavDistance', () {
    test('rounds meters and kilometers for Russian labels', () {
      final s = AppStrings.ru;

      expect(formatNavDistance(0, s), '0 м');
      expect(formatNavDistance(9, s), '10 м');
      expect(formatNavDistance(237, s), '230 м');
      expect(formatNavDistance(999, s), '990 м');
      expect(formatNavDistance(1000, s), '1,0 км');
      expect(formatNavDistance(1600, s), '1,6 км');
      expect(formatNavDistance(9999, s), '9,9 км');
      expect(formatNavDistance(10000, s), '10 км');
      expect(formatNavDistance(10600, s), '10 км');
    });

    test('uses an English decimal separator', () {
      final s = AppStrings.en;

      expect(formatNavDistance(1600, s), '1.6 km');
      expect(formatNavDistance(10600, s), '10 km');
    });
  });

  group('PreparedRoute', () {
    test('precomputes distance and returns decreasing remaining distance', () {
      final route = PreparedRoute(const [
        Point(latitude: 0, longitude: 0),
        Point(latitude: 0, longitude: 0.001),
        Point(latitude: 0, longitude: 0.002),
      ]);

      final first = route.match(const Point(latitude: 0, longitude: 0.00025));
      final second = route.match(
        const Point(latitude: 0, longitude: 0.0015),
        hintSegment: first.segment,
      );

      expect(route.totalDistance, closeTo(222.4, 1));
      expect(first.segment, 0);
      expect(second.segment, 1);
      expect(
        route.remainingDistance(second),
        lessThan(route.remainingDistance(first)),
      );
    });

    test('precomputes the next turn', () {
      final route = PreparedRoute(const [
        Point(latitude: 0, longitude: 0),
        Point(latitude: 0.001, longitude: 0),
        Point(latitude: 0.001, longitude: 0.001),
      ]);

      final match = route.match(const Point(latitude: 0.0002, longitude: 0));
      final turn = route.nextTurn(match);

      expect(turn, isNotNull);
      expect(turn!.direction, TurnDirection.right);
      expect(turn.distanceMeters, closeTo(89, 2));
    });

    test('falls back to a full scan after a large position jump', () {
      final points = List.generate(
        101,
        (index) => Point(latitude: 0, longitude: index * 0.001),
      );
      final route = PreparedRoute(points);

      final match = route.match(
        const Point(latitude: 0, longitude: 0.0905),
        hintSegment: 0,
      );

      expect(match.segment, 90);
      expect(match.distanceFromRoute, lessThan(1));
    });
  });
}
