import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/route_result.dart';
import 'app_providers.dart';
import 'filters_provider.dart';
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

enum DestinationMode { routeToAddress, nearestParking }

final destinationModeProvider = StateProvider<DestinationMode>(
  (ref) => DestinationMode.nearestParking,
);

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

final searchBiasProvider = StateProvider<SearchBias?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');

class RoutingNotifier extends StateNotifier<RoutingState> {
  RoutingNotifier(this._ref) : super(const RoutingState.idle());

  final Ref _ref;
  CancelToken? _cancelToken;
  int _requestGeneration = 0;

  Future<void> searchParking({
    required double originLat,
    required double originLon,
  }) async {
    final generation = ++_requestGeneration;
    _cancelToken?.cancel('Superseded by a newer routing request');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    state = const RoutingState.searching();
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
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (generation != _requestGeneration) return;
      if (e is DioException && e.response != null) {
        state = RoutingState.error(
          '${e.response!.statusCode}: ${e.response!.data}',
        );
      } else {
        state = RoutingState.error(e.toString());
      }
    }
  }

  Future<void> buildRoute({
    required double originLat,
    required double originLon,
    required int selectedZoneId,
  }) async {
    final generation = ++_requestGeneration;
    _cancelToken?.cancel('Superseded by a newer routing request');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    state = const RoutingState.searching();
    try {
      final destination = _ref.read(destinationProvider);
      final timeMode = _ref.read(timeSelectorProvider);
      final useForecast = timeMode.maybeWhen(
        future: (_) => true,
        orElse: () => null,
      );
      final route = await _ref
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
      state = RoutingState.routePreview(route);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (generation != _requestGeneration) return;
      if (e is DioException && e.response != null) {
        state = RoutingState.error(
          '${e.response!.statusCode}: ${e.response!.data}',
        );
      } else {
        state = RoutingState.error(e.toString());
      }
    }
  }

  void reset() {
    _requestGeneration++;
    _cancelToken?.cancel('Routing reset');
    _cancelToken = null;
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
