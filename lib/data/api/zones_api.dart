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
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      '/zones',
      queryParameters: {
        'bbox': bbox,
        'view': view,
        'is_active': ?isActive,
        'min_free_count': ?minFreeCount,
        'min_confidence': ?minConfidence,
        'max_pay': ?maxPay,
        'include_private': ?includePrivate,
        'hide_location_types': ?hideLocationTypes,
      },
      cancelToken: cancelToken,
    );
    return (response.data as List)
        .map((e) => ZoneMapItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ZoneDto> getZone(int zoneId) async {
    final response = await _dio.get('/zones/$zoneId');
    return ZoneDto.fromJson(response.data as Map<String, dynamic>);
  }
}
