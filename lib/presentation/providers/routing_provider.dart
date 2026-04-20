import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/route_result.dart';
import 'app_providers.dart';

part 'routing_provider.freezed.dart';

@freezed
class RoutingState with _$RoutingState {
  const factory RoutingState.idle() = _Idle;
  const factory RoutingState.searching() = _Searching;
  const factory RoutingState.candidates(List<RouteCandidate> candidates) = _Candidates;
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

class RoutingNotifier extends StateNotifier<RoutingState> {
  RoutingNotifier(this._ref) : super(const RoutingState.idle());

  final Ref _ref;

  Future<void> searchParking({
    required double originLat,
    required double originLon,
  }) async {
    state = const RoutingState.searching();
    try {
      final destination = _ref.read(destinationProvider);
      final candidates = await _ref.read(routingRepositoryProvider).searchParking(
            originLat: originLat,
            originLon: originLon,
            destinationLat: destination?.latitude,
            destinationLon: destination?.longitude,
          );
      state = RoutingState.candidates(candidates);
    } catch (e) {
      state = RoutingState.error(e.toString());
    }
  }

  Future<void> buildRoute({
    required double originLat,
    required double originLon,
    required int selectedZoneId,
  }) async {
    state = const RoutingState.searching();
    try {
      final destination = _ref.read(destinationProvider);
      final route = await _ref.read(routingRepositoryProvider).createRoute(
            originLat: originLat,
            originLon: originLon,
            destinationLat: destination?.latitude,
            destinationLon: destination?.longitude,
            selectedZoneId: selectedZoneId,
          );
      state = RoutingState.routePreview(route);
    } catch (e) {
      state = RoutingState.error(e.toString());
    }
  }

  void reset() => state = const RoutingState.idle();
}

final routingProvider =
    StateNotifierProvider<RoutingNotifier, RoutingState>((ref) => RoutingNotifier(ref));
