import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../api/routing_api.dart';
import '../models/routing_models.dart';
import '../../domain/models/route_result.dart';

class RoutingRepository {
  final RoutingApi _api;

  RoutingRepository(this._api);

  Future<List<RouteCandidate>> searchParking({
    required double originLat,
    required double originLon,
    double? destinationLat,
    double? destinationLon,
    int? maxPay,
    double? minConfidence,
  }) async {
    final request = RoutingSearchRequestDto(
      mode: destinationLat != null ? 'route_to_destination' : 'find_parking',
      origin: LocationDto(latitude: originLat, longitude: originLon),
      destination: destinationLat != null
          ? LocationDto(latitude: destinationLat, longitude: destinationLon!)
          : null,
      maxPay: maxPay,
      minConfidence: minConfidence,
    );
    final response = await _api.searchParking(request);
    return response.candidates.map(_mapCandidate).toList();
  }

  Future<ActiveRoute> createRoute({
    required double originLat,
    required double originLon,
    double? destinationLat,
    double? destinationLon,
    required int selectedZoneId,
  }) async {
    final request = RoutingSearchRequestDto(
      mode: destinationLat != null ? 'route_to_destination' : 'find_parking',
      origin: LocationDto(latitude: originLat, longitude: originLon),
      destination: destinationLat != null
          ? LocationDto(latitude: destinationLat, longitude: destinationLon!)
          : null,
    );
    final dto = await _api.createRoute(request, selectedZoneId: selectedZoneId);
    return _mapRoute(dto);
  }

  RouteCandidate _mapCandidate(RouteCandidateDto dto) => RouteCandidate(
        zoneId: dto.zoneId,
        rank: dto.rank,
        freeCount: dto.freeCount,
        confidence: dto.confidence,
        pay: dto.pay,
        distanceToDestinationMeters: dto.distanceToDestinationMeters,
        durationFromOriginSeconds: dto.durationFromOriginSeconds,
        predictedFreeCount: dto.predictedFreeCount,
        eta: dto.eta,
        routePolyline: _parsePolyline(dto.routeGeometry),
      );

  ActiveRoute _mapRoute(RouteDto dto) => ActiveRoute(
        routeId: dto.routeId,
        status: dto.status,
        selectedZoneId: dto.selectedZoneId ?? 0,
        arrivalTime: dto.arrivalTime,
        deeplinkUrl: dto.deeplinkUrl,
        routePolyline: _parsePolyline(dto.routeGeometry),
        candidates: dto.candidates?.map(_mapCandidate).toList() ?? [],
      );

  List<Point>? _parsePolyline(Map<String, dynamic>? geometry) {
    if (geometry == null) return null;
    final coordinates = geometry['coordinates'] as List?;
    if (coordinates == null) return null;
    return coordinates.map((c) {
      final coord = c as List;
      return Point(latitude: (coord[1] as num).toDouble(), longitude: (coord[0] as num).toDouble());
    }).toList();
  }
}
