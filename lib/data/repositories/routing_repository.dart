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
    int? minFreeCount,
    double? minConfidence,
    bool? useForecast,
  }) async {
    final request = RoutingSearchRequestDto(
      mode: destinationLat != null ? 'route_to_destination' : 'find_parking',
      origin: LocationDto(latitude: originLat, longitude: originLon),
      destination: destinationLat != null
          ? LocationDto(latitude: destinationLat, longitude: destinationLon!)
          : null,
      maxPay: maxPay,
      minFreeCount: minFreeCount,
      minConfidence: minConfidence,
      useForecast: useForecast,
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
    bool? useForecast,
  }) async {
    final request = RoutingSearchRequestDto(
      mode: destinationLat != null ? 'route_to_destination' : 'find_parking',
      origin: LocationDto(latitude: originLat, longitude: originLon),
      destination: destinationLat != null
          ? LocationDto(latitude: destinationLat, longitude: destinationLon!)
          : null,
      useForecast: useForecast,
    );
    final dto = await _api.createRoute(request, selectedZoneId: selectedZoneId);
    return _mapRoute(dto);
  }

  RouteCandidate _mapCandidate(RouteCandidateDto dto) => RouteCandidate(
        zoneId: dto.zoneId,
        rank: dto.rank,
        freeCount: dto.currentFreeCount,
        confidence: dto.currentConfidence,
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
        routePolyline: null,
        candidates: dto.selectedCandidate != null
            ? [_mapCandidate(dto.selectedCandidate!)]
            : [],
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
