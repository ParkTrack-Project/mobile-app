import 'dart:async';
import 'dart:io';
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
  final bool isRecalculating;
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
    this.isRecalculating = false,
  });

  bool get hasArrived => remainingMeters < 30;
}

class NavigationNotifier extends Notifier<NavigationData?> {
  StreamSubscription<Position>? _sub;
  Timer? _recalcDebounce;
  Timer? _arrivalTimer;
  DrivingSession? _drivingSession;

  int _segmentIndex = 0;
  double _totalSeconds = 0;
  double _totalMeters = 0;
  List<Point> _route = [];
  double _destLat = 0;
  double _destLon = 0;
  int _zoneId = 0;

  @override
  NavigationData? build() => null;

  Future<void> startNavigation({
    required int zoneId,
    required List<Point> route,
    required double totalSeconds,
    required double totalMeters,
    required double destLat,
    required double destLon,
  }) async {
    _cleanupTimers();
    await _sub?.cancel();

    _segmentIndex = 0;
    _totalSeconds = totalSeconds;
    _totalMeters = totalMeters;
    _route = route;
    _destLat = destLat;
    _destLon = destLon;
    _zoneId = zoneId;

    _sub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(_onPosition);
  }

  void stop() {
    _cleanupTimers();
    _sub?.cancel();
    _sub = null;
    _drivingSession?.close();
    _drivingSession = null;
    state = null;
  }

  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ParkTrack',
          notificationText: 'Навигация активна',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  void _cleanupTimers() {
    _recalcDebounce?.cancel();
    _recalcDebounce = null;
    _arrivalTimer?.cancel();
    _arrivalTimer = null;
  }

  void _onPosition(Position pos) {
    final current = Point(latitude: pos.latitude, longitude: pos.longitude);
    final closest = closestOnRoute(current, _route);

    if (closest.segment > _segmentIndex) {
      _segmentIndex = closest.segment;
    }

    final remaining = remainingRouteDistance(_route, _segmentIndex, closest.t);
    final perp = perpDistToRoute(current, _route, _segmentIndex, closest.t);
    final remainingSecs = _totalMeters > 0
        ? (_totalSeconds * remaining / _totalMeters).round()
        : 0;
    final nextTurn = findNextTurn(_route, _segmentIndex, current);
    final isOff = perp > 60;

    state = NavigationData(
      zoneId: _zoneId,
      route: _route,
      remainingMeters: remaining,
      remainingSeconds: remainingSecs,
      speedKmh: (pos.speed * 3.6).clamp(0.0, 300.0),
      currentPosition: current,
      heading: pos.heading >= 0 ? pos.heading : 0,
      nextTurn: nextTurn,
      isOffRoute: isOff,
      isRecalculating: state?.isRecalculating ?? false,
    );

    // Auto-stop 3 s after arrival
    if (remaining < 30) {
      _recalcDebounce?.cancel();
      _recalcDebounce = null;
      _arrivalTimer ??= Timer(const Duration(seconds: 3), stop);
    } else {
      if (_arrivalTimer != null) {
        _arrivalTimer?.cancel();
        _arrivalTimer = null;
      }

      // Debounced off-route recalculation
      if (isOff) {
        _recalcDebounce ??= Timer(const Duration(seconds: 5), () => _recalculate(current));
      } else {
        _recalcDebounce?.cancel();
        _recalcDebounce = null;
      }
    }
  }

  Future<void> _recalculate(Point from) async {
    _recalcDebounce = null;
    final current = state;
    if (current == null) return;

    state = NavigationData(
      zoneId: current.zoneId,
      route: current.route,
      remainingMeters: current.remainingMeters,
      remainingSeconds: current.remainingSeconds,
      speedKmh: current.speedKmh,
      currentPosition: current.currentPosition,
      heading: current.heading,
      isOffRoute: true,
      isRecalculating: true,
    );

    try {
      await _drivingSession?.close();
      final rws = YandexDriving.requestRoutes(
        points: [
          RequestPoint(point: from, requestPointType: RequestPointType.wayPoint),
          RequestPoint(
            point: Point(latitude: _destLat, longitude: _destLon),
            requestPointType: RequestPointType.wayPoint,
          ),
        ],
        drivingOptions: const DrivingOptions(routesCount: 1),
      );
      _drivingSession = rws.session;
      final result = await rws.result;
      await rws.session.close();
      _drivingSession = null;

      final dr = result.routes?.firstOrNull;
      if (dr == null || state == null) return;

      _route = dr.geometry;
      _segmentIndex = 0;
      _totalSeconds = dr.metadata.weight.timeWithTraffic.value ?? _totalSeconds;
      _totalMeters = dr.metadata.weight.distance.value ?? _totalMeters;

      if (_totalMeters == 0 && _route.length >= 2) {
        for (int i = 0; i < _route.length - 1; i++) {
          _totalMeters += navDistanceM(_route[i], _route[i + 1]);
        }
        _totalSeconds = _totalMeters / 10;
      }

      final s = state!;
      state = NavigationData(
        zoneId: s.zoneId,
        route: _route,
        remainingMeters: _totalMeters,
        remainingSeconds: _totalSeconds.round(),
        speedKmh: s.speedKmh,
        currentPosition: s.currentPosition,
        heading: s.heading,
        isOffRoute: false,
        isRecalculating: false,
      );
    } catch (_) {
      final s = state;
      if (s != null) {
        state = NavigationData(
          zoneId: s.zoneId,
          route: s.route,
          remainingMeters: s.remainingMeters,
          remainingSeconds: s.remainingSeconds,
          speedKmh: s.speedKmh,
          currentPosition: s.currentPosition,
          heading: s.heading,
          isOffRoute: true,
          isRecalculating: false,
        );
      }
    }
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationData?>(NavigationNotifier.new);
