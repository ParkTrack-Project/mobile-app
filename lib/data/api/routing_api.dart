import 'package:dio/dio.dart';
import '../models/routing_models.dart';

class RoutingApi {
  final Dio _dio;

  RoutingApi(this._dio);

  Future<RoutingSearchResponseDto> searchParking(
    RoutingSearchRequestDto request,
  ) async {
    final response = await _dio.post('/routing/search', data: request.toJson());
    return RoutingSearchResponseDto.fromJson(
        response.data as Map<String, dynamic>);
  }

  Future<RouteDto> createRoute(RoutingSearchRequestDto request,
      {int? selectedZoneId}) async {
    final data = {
      ...request.toJson(),
      if (selectedZoneId != null) 'selected_zone_id': selectedZoneId,
    };
    final response = await _dio.post('/routing/new', data: data);
    return RouteDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<RouteDto> getRoute(int routeId) async {
    final response = await _dio.get('/routing/$routeId');
    return RouteDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<RouteDto> updateRoute(
    int routeId, {
    String? status,
    int? selectedZoneId,
  }) async {
    final response = await _dio.put('/routing/$routeId', data: {
      if (status != null) 'status': status,
      if (selectedZoneId != null) 'selected_zone_id': selectedZoneId,
    });
    return RouteDto.fromJson(response.data as Map<String, dynamic>);
  }
}
