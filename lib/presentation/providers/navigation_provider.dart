import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../core/utils/nav_math.dart';

class NavigationData {
  final int zoneId;
  final List<Point> route;
  final double remainingMeters;
  final int remainingSeconds;
  final double speedKmh;
  final NavTurn? nextTurn;
  final bool isOffRoute;
  final Point currentPosition;
  final double heading;

  const NavigationData({
    required this.zoneId,
    required this.route,
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.speedKmh,
    required this.currentPosition,
    required this.heading,
    this.nextTurn,
    this.isOffRoute = false,
  });

  bool get hasArrived => remainingMeters < 30;

  NavigationData copyWith({
    double? remainingMeters,
    int? remainingSeconds,
    double? speedKmh,
    NavTurn? nextTurn,
    bool clearTurn = false,
    bool? isOffRoute,
    Point? currentPosition,
    double? heading,
  }) {
    return NavigationData(
      zoneId: zoneId,
      route: route,
      remainingMeters: remainingMeters ?? this.remainingMeters,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      speedKmh: speedKmh ?? this.speedKmh,
      nextTurn: clearTurn ? null : (nextTurn ?? this.nextTurn),
      isOffRoute: isOffRoute ?? this.isOffRoute,
      currentPosition: currentPosition ?? this.currentPosition,
      heading: heading ?? this.heading,
    );
  }
}

class NavigationNotifier extends Notifier<NavigationData?> {
  StreamSubscription<Position>? _sub;
  int _segmentIndex = 0;
  double _totalSeconds = 0;
  double _totalMeters = 0;

  @override
  NavigationData? build() => null;

  Future<void> startNavigation({
    required int zoneId,
    required List<Point> route,
    required double totalSeconds,
    required double totalMeters,
  }) async {
    await _sub?.cancel();
    _segmentIndex = 0;
    _totalSeconds = totalSeconds;
    _totalMeters = totalMeters;

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) => _onPosition(pos, zoneId, route));
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    state = null;
  }

  void _onPosition(Position pos, int zoneId, List<Point> route) {
    final current = Point(latitude: pos.latitude, longitude: pos.longitude);
    final closest = closestOnRoute(current, route);

    if (closest.segment > _segmentIndex) {
      _segmentIndex = closest.segment;
    }

    final remaining = remainingRouteDistance(route, _segmentIndex, closest.t);
    final perp = perpDistToRoute(current, route, _segmentIndex, closest.t);
    final remainingSecs = _totalMeters > 0
        ? (_totalSeconds * remaining / _totalMeters).round()
        : 0;

    final nextTurn = findNextTurn(route, _segmentIndex, current);

    state = NavigationData(
      zoneId: zoneId,
      route: route,
      remainingMeters: remaining,
      remainingSeconds: remainingSecs,
      speedKmh: (pos.speed * 3.6).clamp(0, 300),
      currentPosition: current,
      heading: pos.heading >= 0 ? pos.heading : 0,
      nextTurn: nextTurn,
      isOffRoute: perp > 60,
    );
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationData?>(NavigationNotifier.new);
