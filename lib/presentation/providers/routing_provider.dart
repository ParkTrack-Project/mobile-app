import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/route_result.dart';
import 'app_providers.dart';
import 'filters_provider.dart';
import 'parking_search_provider.dart';
import 'time_selector_provider.dart';

part 'routing_provider.freezed.dart';

@freezed
class RoutingState with _$RoutingState {
  const factory RoutingState.idle() = _Idle;
  const factory RoutingState.searching() = _Searching;
  const factory RoutingState.candidates(List<RouteCandidate> candidates) =
      _Candidates;
  const factory RoutingState.routePreview(ActiveRoute route) = _RoutePreview;
  const factory RoutingState.error(String message) = _Error;
}

@freezed
class Destination with _$Destination {
  const factory Destination({
    required double latitude,
    required double longitude,
    String? name,
  }) = _Destination;
}

final destinationProvider = StateProvider<Destination?>((ref) => null);

class SearchBias {
  const SearchBias({
    required this.latitude,
    required this.longitude,
    this.south,
    this.west,
    this.north,
    this.east,
  });

  final double latitude;
  final double longitude;
  final double? south;
  final double? west;
  final double? north;
  final double? east;
}

class RoutingFailureEvent {
  const RoutingFailureEvent({
    required this.id,
    required this.failure,
    required this.retry,
  });

  final int id;
  final AppFailure failure;
  final Future<void> Function() retry;
}

final routingFailureProvider = StateProvider<RoutingFailureEvent?>(
  (ref) => null,
);

final searchBiasProvider = StateProvider<SearchBias?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');

typedef RouteGeometry = ({
  List<Point> points,
  int distanceMeters,
  int durationSeconds,
});

class RoutingNotifier extends StateNotifier<RoutingState> {
  RoutingNotifier(this._ref) : super(const RoutingState.idle());

  final Ref _ref;
  CancelToken? _cancelToken;
  int _requestGeneration = 0;
  int _failureGeneration = 0;
  RoutingState? _stableState;

  void _startRequest({bool preserveStableState = true}) {
    _ref.read(routingFailureProvider.notifier).state = null;
    final stable = preserveStableState
        ? state.maybeWhen(
            candidates: (_) => state,
            routePreview: (_) => state,
            orElse: () => null,
          )
        : null;
    if (stable != null) {
      _stableState = stable;
    } else {
      state = const RoutingState.searching();
    }
  }

  void _publishFailure(
    Object error, {
    required AppFailureKind fallback,
    required Future<void> Function() retry,
  }) {
    final failure = AppFailure.from(error, fallback: fallback);
    final cached = _stableState;
    if (failure.isRecoverable && cached != null) {
      state = cached;
    } else {
      state = RoutingState.error(failure.kind.name);
    }
    _ref.read(routingFailureProvider.notifier).state = RoutingFailureEvent(
      id: ++_failureGeneration,
      failure: failure,
      retry: retry,
    );
  }

  Future<void> searchParking({
    required double originLat,
    required double originLon,
  }) async {
    final generation = ++_requestGeneration;
    _cancelToken?.cancel('Superseded by a newer routing request');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _ref.read(parkingSearchProvider.notifier).startSearch();
    _stableState = null;
    _startRequest(preserveStableState: false);
    try {
      final destination = _ref.read(destinationProvider);
      final filters = _ref.read(filtersProvider);
      final useForecast = true;
      final candidates = await _ref
          .read(routingRepositoryProvider)
          .searchParking(
            originLat: originLat,
            originLon: originLon,
            destinationLat: destination?.latitude,
            destinationLon: destination?.longitude,
            maxPay: filters.maxPayPerHour,
            minConfidence: filters.minConfidence > 0
                ? filters.minConfidence
                : null,
            minFreeCount: filters.hideNoFreeSpots ? 1 : null,
            useForecast: useForecast,
            cancelToken: cancelToken,
          );
      if (generation != _requestGeneration || cancelToken.isCancelled) return;
      state = RoutingState.candidates(candidates);
      _stableState = state;
      _ref.read(parkingSearchProvider.notifier).showResults(candidates);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (generation != _requestGeneration) return;
      _ref.read(parkingSearchProvider.notifier).showSearchError();
      _publishFailure(
        e,
        fallback: AppFailureKind.network,
        retry: () => searchParking(originLat: originLat, originLon: originLon),
      );
    }
  }

  Future<void> buildRoute({
    required double originLat,
    required double originLon,
    required int selectedZoneId,
    List<Point>? routePolyline,
    int? routeDistanceMeters,
    int? routeDurationSeconds,
    Future<RouteGeometry?> Function()? routeGeometryFallback,
  }) async {
    final generation = ++_requestGeneration;
    _cancelToken?.cancel('Superseded by a newer routing request');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _startRequest();
    try {
      final destination = _ref.read(destinationProvider);
      final timeMode = _ref.read(timeSelectorProvider);
      final useForecast = timeMode.maybeWhen(
        future: (_) => true,
        orElse: () => null,
      );
      var route = await _ref
          .read(routingRepositoryProvider)
          .createRoute(
            originLat: originLat,
            originLon: originLon,
            destinationLat: destination?.latitude,
            destinationLon: destination?.longitude,
            selectedZoneId: selectedZoneId,
            useForecast: useForecast,
            cancelToken: cancelToken,
          );
      if (generation != _requestGeneration || cancelToken.isCancelled) return;
      RouteGeometry? fallbackGeometry;
      final primaryPolyline = routePolyline ?? route.routePolyline;
      if ((primaryPolyline == null || primaryPolyline.length < 2) &&
          routeGeometryFallback != null) {
        fallbackGeometry = await routeGeometryFallback();
        if (generation != _requestGeneration || cancelToken.isCancelled) {
          return;
        }
      }
      final resolvedPolyline =
          routePolyline ?? route.routePolyline ?? fallbackGeometry?.points;
      if (resolvedPolyline == null || resolvedPolyline.length < 2) {
        throw StateError('The routing services returned no driving route');
      }
      route = route.copyWith(
        routePolyline: resolvedPolyline,
        routeDistanceMeters:
            routeDistanceMeters ??
            route.routeDistanceMeters ??
            fallbackGeometry?.distanceMeters,
        routeDurationSeconds:
            routeDurationSeconds ??
            route.routeDurationSeconds ??
            fallbackGeometry?.durationSeconds,
      );
      state = RoutingState.routePreview(route);
      _stableState = state;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (generation != _requestGeneration) return;
      _ref.read(parkingSearchProvider.notifier).backToResults();
      _publishFailure(
        e,
        fallback: AppFailureKind.routeLoad,
        retry: () => buildRoute(
          originLat: originLat,
          originLon: originLon,
          selectedZoneId: selectedZoneId,
          routePolyline: routePolyline,
          routeDistanceMeters: routeDistanceMeters,
          routeDurationSeconds: routeDurationSeconds,
          routeGeometryFallback: routeGeometryFallback,
        ),
      );
    }
  }

  Future<void> loadRoute(int routeId) async {
    final generation = ++_requestGeneration;
    _cancelToken?.cancel('Superseded by a shared route request');
    _cancelToken = null;
    _stableState = null;
    _startRequest(preserveStableState: false);
    try {
      final route = await _ref
          .read(routingRepositoryProvider)
          .getRoute(routeId);
      if (generation != _requestGeneration) return;
      state = RoutingState.routePreview(route);
      _stableState = state;
    } catch (error) {
      if (generation != _requestGeneration) return;
      _publishFailure(
        error,
        fallback: AppFailureKind.routeLoad,
        retry: () => loadRoute(routeId),
      );
    }
  }

  void reset() {
    _requestGeneration++;
    _cancelToken?.cancel('Routing reset');
    _cancelToken = null;
    _stableState = null;
    _ref.read(routingFailureProvider.notifier).state = null;
    _ref.read(parkingSearchProvider.notifier).clear();
    state = const RoutingState.idle();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Routing provider disposed');
    super.dispose();
  }
}

final routingProvider = StateNotifierProvider<RoutingNotifier, RoutingState>(
  (ref) => RoutingNotifier(ref),
);
