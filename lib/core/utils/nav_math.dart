import 'dart:math';
import 'package:yandex_mapkit/yandex_mapkit.dart';

const _kEarthRadius = 6371000.0;

enum TurnDirection { left, slightLeft, straight, slightRight, right, uTurn, arrive }

class NavTurn {
  final TurnDirection direction;
  final double distanceMeters;
  const NavTurn(this.direction, this.distanceMeters);
}

double navDistanceM(Point a, Point b) {
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dlat = (b.latitude - a.latitude) * pi / 180;
  final dlon = (b.longitude - a.longitude) * pi / 180;
  final h = sin(dlat / 2) * sin(dlat / 2) +
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

({int segment, double t}) closestOnRoute(Point p, List<Point> pts) {
  int bestSeg = 0;
  double bestT = 0;
  double bestDist = double.infinity;
  for (int i = 0; i < pts.length - 1; i++) {
    final a = pts[i];
    final b = pts[i + 1];
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final len2 = dx * dx + dy * dy;
    double t = 0;
    if (len2 > 1e-18) {
      t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) / len2;
      t = t.clamp(0.0, 1.0);
    }
    final proj = Point(
      latitude: a.latitude + t * dy,
      longitude: a.longitude + t * dx,
    );
    final d = navDistanceM(p, proj);
    if (d < bestDist) {
      bestDist = d;
      bestSeg = i;
      bestT = t;
    }
  }
  return (segment: bestSeg, t: bestT);
}

double remainingRouteDistance(List<Point> pts, int seg, double t) {
  if (pts.length < 2 || seg >= pts.length - 1) return 0;
  final a = pts[seg];
  final b = pts[seg + 1];
  final proj = Point(
    latitude: a.latitude + t * (b.latitude - a.latitude),
    longitude: a.longitude + t * (b.longitude - a.longitude),
  );
  double dist = navDistanceM(proj, b);
  for (int i = seg + 1; i < pts.length - 1; i++) {
    dist += navDistanceM(pts[i], pts[i + 1]);
  }
  return dist;
}

double perpDistToRoute(Point p, List<Point> pts, int seg, double t) {
  if (pts.isEmpty || seg >= pts.length - 1) return 0;
  final a = pts[seg];
  final b = pts[seg + 1];
  final proj = Point(
    latitude: a.latitude + t * (b.latitude - a.latitude),
    longitude: a.longitude + t * (b.longitude - a.longitude),
  );
  return navDistanceM(p, proj);
}

NavTurn? findNextTurn(List<Point> pts, int fromSeg, Point currentPos) {
  if (pts.length < 3) return null;
  double accDist = fromSeg < pts.length - 1
      ? navDistanceM(currentPos, pts[fromSeg + 1])
      : 0;
  for (int i = max(fromSeg + 1, 1); i < pts.length - 1; i++) {
    final b1 = navBearingDeg(pts[i - 1], pts[i]);
    final b2 = navBearingDeg(pts[i], pts[i + 1]);
    final diff = _bearingDiff(b2, b1);
    if (diff.abs() >= 18) {
      return NavTurn(_classifyTurn(diff), accDist);
    }
    accDist += navDistanceM(pts[i], pts[i + 1]);
    if (accDist > 3000) break;
  }
  return null;
}

TurnDirection _classifyTurn(double diff) {
  final a = diff.abs();
  if (a > 150) return TurnDirection.uTurn;
  if (diff > 60) return TurnDirection.right;
  if (diff > 18) return TurnDirection.slightRight;
  if (diff < -60) return TurnDirection.left;
  if (diff < -18) return TurnDirection.slightLeft;
  return TurnDirection.straight;
}

String formatNavDistance(double meters) {
  if (meters < 950) return '${meters.round()} м';
  return '${(meters / 1000).toStringAsFixed(1)} км';
}

String formatNavDuration(int seconds) {
  if (seconds < 3600) return '${(seconds / 60).round()} мин';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return m == 0 ? '${h}ч' : '${h}ч ${m}мин';
}
