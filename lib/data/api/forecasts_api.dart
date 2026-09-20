import 'package:dio/dio.dart';
import 'map_query.dart';

class ForecastsApi {
  final Dio _dio;

  ForecastsApi(this._dio);

  Future<List<Map<String, dynamic>>> getForecastsMap({
    required String bbox,
    required String at,
    bool? isActive,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      mapQueryPath(
        '/forecasts',
        bbox: bbox,
        parameters: {
          'at': at,
          'view': 'map',
          'latest_model_only': true,
          'is_active': isActive,
        },
      ),
      cancelToken: cancelToken,
    );
    return (response.data as List).cast<Map<String, dynamic>>();
  }
}
