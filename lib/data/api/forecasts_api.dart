import 'package:dio/dio.dart';

class ForecastsApi {
  final Dio _dio;

  ForecastsApi(this._dio);

  Future<List<Map<String, dynamic>>> getForecastsMap({
    required String bbox,
    required String at,
  }) async {
    final response = await _dio.get('/forecasts', queryParameters: {
      'bbox': bbox,
      'at': at,
      'view': 'map',
      'latest_model_only': true,
    });
    return (response.data as List).cast<Map<String, dynamic>>();
  }
}
