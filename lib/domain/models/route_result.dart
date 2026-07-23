import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

part 'route_result.freezed.dart';

@freezed
class RouteCandidate with _$RouteCandidate {
  const factory RouteCandidate({
    required int zoneId,
    required int rank,
    required int freeCount,
    required double confidence,
    required int pay,
    int? distanceToDestinationMeters,
    int? durationFromOriginSeconds,
    int? predictedFreeCount,
    String? eta,
    List<Point>? routePolyline,
  }) = _RouteCandidate;
}

@freezed
class ActiveRoute with _$ActiveRoute {
  const factory ActiveRoute({
    required int routeId,
    required String status,
    required int selectedZoneId,
    String? arrivalTime,
    String? deeplinkUrl,
    List<Point>? routePolyline,
    int? routeDistanceMeters,
    int? routeDurationSeconds,
    required List<RouteCandidate> candidates,
  }) = _ActiveRoute;
}
