import 'package:dio/dio.dart';
import '../models/zone_models.dart';

class ZonesApi {
  final Dio _dio;

  ZonesApi(this._dio);

  Future<List<ZoneMapItemDto>> getZones({
    required String bbox,
    String view = 'map',
    bool? isActive,
    int? minFreeCount,
    double? minConfidence,
    int? maxPay,
    bool? includePrivate,
    String? hideLocationTypes,
  }) async {
    final response = await _dio.get('/zones', queryParameters: {
      'bbox': bbox,
      'view': view,
      if (isActive != null) 'is_active': isActive,
      if (minFreeCount != null) 'min_free_count': minFreeCount,
      if (minConfidence != null) 'min_confidence': minConfidence,
      if (maxPay != null) 'max_pay': maxPay,
      if (includePrivate != null) 'include_private': includePrivate,
      if (hideLocationTypes != null) 'hide_location_types': hideLocationTypes,
    });
    return (response.data as List)
        .map((e) => ZoneMapItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ZoneDto> getZone(int zoneId) async {
    final response = await _dio.get('/zones/$zoneId');
    return ZoneDto.fromJson(response.data as Map<String, dynamic>);
  }
}
