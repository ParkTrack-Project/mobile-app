import 'dart:math';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../localization/app_localizations.dart';

const _kEarthRadius = 6371000.0;

enum TurnDirection {
  left,
  slightLeft,
  straight,
  slightRight,
  right,
  uTurn,
  arrive,
}

class NavTurn {
  final TurnDirection direction;
  final double distanceMeters;
  const NavTurn(this.direction, this.distanceMeters);
}

class RouteMatch {
  const RouteMatch({
    required this.segment,
    required this.t,
    required this.projectedPoint,
    required this.distanceFromRoute,
  });

  final int segment;
  final double t;
  final Point projectedPoint;
  final double distanceFromRoute;
}

class _PreparedTurn {
  const _PreparedTurn(this.pointIndex, this.direction);

  final int pointIndex;
  final TurnDirection direction;
}

/// Immutable route index used by the navigation hot path.
///
/// Segment lengths, remaining distances and turns are calculated once when a
/// route is received. Position updates then inspect only a small window around
/// the last matched segment instead of repeatedly walking the whole polyline.
class PreparedRoute {
  PreparedRoute(List<Point> points)
    : points = List.unmodifiable(points),
      _segmentLengths = _buildSegmentLengths(points),
      _remainingAtPoint = _buildRemainingDistances(points),
      _turns = _buildTurns(points);

  final List<Point> points;
  final List<double> _segmentLengths;
  final List<double> _remainingAtPoint;
  final List<_PreparedTurn> _turns;

  bool get isValid => points.length >= 2;
  double get totalDistance =>
      _remainingAtPoint.isEmpty ? 0 : _remainingAtPoint.first;

  RouteMatch match(Point point, {int hintSegment = 0}) {
    if (!isValid) {
      return RouteMatch(
        segment: 0,
        t: 0,
        projectedPoint: point,
        distanceFromRoute: 0,
      );
    }

    final lastSegment = points.length - 2;
    final start = max(0, hintSegment - 5);
    final end = min(lastSegment, hintSegment + 40);
    var best = _matchRange(point, start, end);

    // A large jump, GPS recovery or app resume may put the user outside the
    // local search window. The expensive full scan is reserved for that case.
    if (best.distanceFromRoute > 200 && (start > 0 || end < lastSegment)) {
      best = _matchRange(point, 0, lastSegment);
    }
    return best;
  }

  double remainingDistance(RouteMatch match) {
    if (!isValid || match.segment >= _segmentLengths.length) return 0;
    final segmentRemainder =
        _segmentLengths[match.segment] * (1 - match.t.clamp(0.0, 1.0));
    return segmentRemainder + _remainingAtPoint[match.segment + 1];
  }

  NavTurn? nextTurn(RouteMatch match) {
    if (_turns.isEmpty) return null;
    final remaining = remainingDistance(match);
    for (final turn in _turns) {
      if (turn.pointIndex < match.segment + 1) continue;
      final distance = remaining - _remainingAtPoint[turn.pointIndex];
      if (distance > 3000) return null;
      return NavTurn(turn.direction, max(0, distance));
    }
    return null;
  }

  RouteMatch _matchRange(Point point, int start, int end) {
    var bestSegment = start;
    var bestT = 0.0;
    var bestDistance = double.infinity;
    var bestPoint = points[start];

    for (var i = start; i <= end; i++) {
      final a = points[i];
      final b = points[i + 1];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final lengthSquared = dx * dx + dy * dy;
      var t = 0.0;
      if (lengthSquared > 1e-18) {
        t =
            ((point.longitude - a.longitude) * dx +
                (point.latitude - a.latitude) * dy) /
            lengthSquared;
        t = t.clamp(0.0, 1.0);
      }
      final projected = Point(
        latitude: a.latitude + t * dy,
        longitude: a.longitude + t * dx,
      );
      final distance = navDistanceM(point, projected);
      if (distance < bestDistance) {
        bestSegment = i;
        bestT = t;
        bestDistance = distance;
        bestPoint = projected;
      }
    }
    return RouteMatch(
      segment: bestSegment,
      t: bestT,
      projectedPoint: bestPoint,
      distanceFromRoute: bestDistance,
    );
  }

  static List<double> _buildSegmentLengths(List<Point> points) {
    return [
      for (var i = 0; i < points.length - 1; i++)
        navDistanceM(points[i], points[i + 1]),
    ];
  }

  static List<double> _buildRemainingDistances(List<Point> points) {
    if (points.isEmpty) return const [];
    final result = List<double>.filled(points.length, 0);
    for (var i = points.length - 2; i >= 0; i--) {
      result[i] = result[i + 1] + navDistanceM(points[i], points[i + 1]);
    }
    return result;
  }

  static List<_PreparedTurn> _buildTurns(List<Point> points) {
    final result = <_PreparedTurn>[];
    for (var i = 1; i < points.length - 1; i++) {
      final before = navBearingDeg(points[i - 1], points[i]);
      final after = navBearingDeg(points[i], points[i + 1]);
      final difference = _bearingDiff(after, before);
      if (difference.abs() >= 18) {
        result.add(_PreparedTurn(i, _classifyTurn(difference)));
      }
    }
    return List.unmodifiable(result);
  }
}

double navDistanceM(Point a, Point b) {
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dlat = (b.latitude - a.latitude) * pi / 180;
  final dlon = (b.longitude - a.longitude) * pi / 180;
  final h =
      sin(dlat / 2) * sin(dlat / 2) +
      cos(lat1) * cos(lat2) * sin(dlon / 2) * sin(dlon / 2);
  return 2 * _kEarthRadius * asin(sqrt(h.clamp(0.0, 1.0)));
}

double navBearingDeg(Point a, Point b) {
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dlon = (b.longitude - a.longitude) * pi / 180;
  final y = sin(dlon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

double _bearingDiff(double to, double from) => (to - from + 540) % 360 - 180;

TurnDirection _classifyTurn(double diff) {
  final a = diff.abs();
  if (a > 150) return TurnDirection.uTurn;
  if (diff > 60) return TurnDirection.right;
  if (diff > 18) return TurnDirection.slightRight;
  if (diff < -60) return TurnDirection.left;
  if (diff < -18) return TurnDirection.slightLeft;
  return TurnDirection.straight;
}

String formatNavDistance(num meters, [AppStrings? s]) {
  final metersSign = s?.metersSign ?? 'm';
  final kmSign = s?.kmSign ?? 'km';
  if (meters < 950) return '${meters.round()} $metersSign';
  return '${(meters / 1000).toStringAsFixed(1)} $kmSign';
}

String formatNavDuration(num seconds, [AppStrings? s]) {
  final minSign = s?.minutesSign ?? 'min';
  final hourSign = s?.hourSign ?? 'h';
  if (seconds < 3600) return '${(seconds / 60).round()} $minSign';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return m == 0 ? '$h $hourSign' : '$h $hourSign $m $minSign';
}
