import 'package:dio/dio.dart';

class OccupancyApi {
  final Dio _dio;

  OccupancyApi(this._dio);

  Future<List<Map<String, dynamic>>> getOccupancyMap({
    required String bbox,
    required String at,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      '/occupancy',
      queryParameters: {
        'bbox': bbox,
        'at': at,
        'view': 'map',
        'latest_only': true,
      },
      cancelToken: cancelToken,
    );
    return (response.data as List).cast<Map<String, dynamic>>();
  }
}
