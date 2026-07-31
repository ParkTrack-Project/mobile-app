import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../core/utils/nav_math.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/yandex_web_route.dart';
import 'app_providers.dart';

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
  PreparedRoute? _preparedRoute;
  double _destLat = 0;
  double _destLon = 0;
  int _zoneId = 0;
  int _navigationGeneration = 0;
  int _offRouteSamples = 0;

  double? _smoothLat;
  double? _smoothLon;
  double? _smoothHeading;

  @override
  NavigationData? build() {
    ref.onDispose(_disposeResources);
    return null;
  }

  Future<void> startNavigation({
    required int zoneId,
    required List<Point> route,
    required Point initialPosition,
    required double totalSeconds,
    required double totalMeters,
    required double destLat,
    required double destLon,
    required AppStrings s,
  }) async {
    _navigationGeneration++;
    _cleanupTimers();
    await _sub?.cancel();

    _segmentIndex = 0;
    _totalSeconds = totalSeconds;
    _totalMeters = totalMeters;
    _route = route;
    _preparedRoute = PreparedRoute(route);
    if (_totalMeters <= 0) {
      _totalMeters = _preparedRoute!.totalDistance;
    }
    if (_totalSeconds <= 0 && _totalMeters > 0) {
      _totalSeconds = _totalMeters / 10;
    }
    _destLat = destLat;
    _destLon = destLon;
    _zoneId = zoneId;
    _smoothLat = null;
    _smoothLon = null;
    _smoothHeading = null;
    _offRouteSamples = 0;

    state = NavigationData(
      zoneId: zoneId,
      route: route,
      remainingMeters: _totalMeters,
      remainingSeconds: _totalSeconds.round(),
      speedKmh: 0,
      currentPosition: initialPosition,
      heading: 0,
    );

    _sub = ref
        .read(preferredLocationServiceProvider)
        .watchCurrentPosition(
          locationSettings: _buildLocationSettings(s),
          preferNetworkInitialFix: true,
        )
        .listen(_onPosition, onError: (_) {});
  }

  void stop() {
    _navigationGeneration++;
    _disposeResources();
    state = null;
  }

  void _disposeResources() {
    _cleanupTimers();
    _sub?.cancel();
    _sub = null;
    _drivingSession?.close();
    _drivingSession = null;
    _preparedRoute = null;
  }

  LocationSettings _buildLocationSettings(AppStrings s) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: s.appTitle,
          notificationText: s.navigationActive,
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

  static const _kAlpha = 0.3;

  double _ema(double raw, double? prev) =>
      prev == null ? raw : prev * (1 - _kAlpha) + raw * _kAlpha;

  double _emaCircular(double raw, double? prev) {
    if (prev == null) return raw;
    final diff = ((raw - prev + 540) % 360) - 180;
    return (prev + _kAlpha * diff + 360) % 360;
  }

  void _onPosition(Position pos) {
    _smoothLat = _ema(pos.latitude, _smoothLat);
    _smoothLon = _ema(pos.longitude, _smoothLon);
    final rawHeading = pos.heading >= 0 ? pos.heading : 0.0;
    _smoothHeading = _emaCircular(rawHeading, _smoothHeading);

    final current = Point(latitude: _smoothLat!, longitude: _smoothLon!);
    final preparedRoute = _preparedRoute;
    if (preparedRoute == null || !preparedRoute.isValid) return;
    final closest = preparedRoute.match(current, hintSegment: _segmentIndex);

    if (closest.segment > _segmentIndex) {
      _segmentIndex = closest.segment;
    }

    final remaining = preparedRoute.remainingDistance(closest);
    final perp = closest.distanceFromRoute;
    final remainingSecs = _totalMeters > 0
        ? (_totalSeconds * remaining / _totalMeters).round()
        : 0;
    final nextTurn = preparedRoute.nextTurn(closest);
    final offRouteThreshold = max(60.0, pos.accuracy * 1.5);
    if (pos.accuracy <= 50 && perp > offRouteThreshold) {
      _offRouteSamples++;
    } else {
      _offRouteSamples = 0;
    }
    final isOff = _offRouteSamples >= 3;

    state = NavigationData(
      zoneId: _zoneId,
      route: _route,
      remainingMeters: remaining,
      remainingSeconds: remainingSecs,
      speedKmh: (pos.speed * 3.6).clamp(0.0, 300.0),
      currentPosition: current,
      heading: _smoothHeading!,
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
        _recalcDebounce ??= Timer(
          const Duration(seconds: 5),
          () => _recalculate(current),
        );
      } else {
        _recalcDebounce?.cancel();
        _recalcDebounce = null;
      }
    }
  }

  Future<void> _recalculate(Point from) async {
    _recalcDebounce = null;
    final generation = _navigationGeneration;
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
      if (kIsWeb) {
        final webRoute = await requestYandexWebRoute(
          fromLatitude: from.latitude,
          fromLongitude: from.longitude,
          toLatitude: _destLat,
          toLongitude: _destLon,
        );
        if (webRoute == null) {
          throw StateError('Yandex Maps did not return a route');
        }
        if (state == null || generation != _navigationGeneration) {
          return;
        }
        _route = webRoute.points;
        _totalSeconds = webRoute.durationSeconds;
        _totalMeters = webRoute.distanceMeters;
      } else {
        await _drivingSession?.close();
        final rws = YandexDriving.requestRoutes(
          points: [
            RequestPoint(
              point: from,
              requestPointType: RequestPointType.wayPoint,
            ),
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
        if (dr == null) {
          throw StateError('Yandex MapKit did not return a route');
        }
        if (state == null || generation != _navigationGeneration) {
          return;
        }
        _route = dr.geometry;
        _totalSeconds =
            dr.metadata.weight.timeWithTraffic.value ?? _totalSeconds;
        _totalMeters = dr.metadata.weight.distance.value ?? _totalMeters;
      }
      _preparedRoute = PreparedRoute(_route);
      _segmentIndex = 0;

      if (_totalMeters == 0 && _preparedRoute!.isValid) {
        _totalMeters = _preparedRoute!.totalDistance;
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
    NotifierProvider<NavigationNotifier, NavigationData?>(
      NavigationNotifier.new,
    );
