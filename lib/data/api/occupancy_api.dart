import 'package:dio/dio.dart';
import 'map_query.dart';

class OccupancyApi {
  final Dio _dio;

  OccupancyApi(this._dio);

  Future<List<Map<String, dynamic>>> getOccupancyMap({
    required String bbox,
    required String at,
    bool? isActive,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      mapQueryPath(
        '/occupancy',
        bbox: bbox,
        parameters: {
          'at': at,
          'view': 'map',
          'latest_only': true,
          'is_active': isActive,
        },
      ),
      cancelToken: cancelToken,
    );
    return (response.data as List).cast<Map<String, dynamic>>();
  }
}
