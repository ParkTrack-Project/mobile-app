import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/api/forecasts_api.dart';
import 'package:mobile/data/api/occupancy_api.dart';

void main() {
  test('occupancy map requests active records', () async {
    final request = await _captureRequest(
      (dio) => OccupancyApi(
        dio,
      ).getOccupancyMap(bbox: '30,59,31,60', at: '2026-08-07T10:00:00Z'),
    );

    expect(request.path, '/occupancy');
    expect(request.queryParameters['is_active'], isTrue);
    expect(request.queryParameters, isNot(contains('latest_only')));
  });

  test('forecasts map requests active records', () async {
    final request = await _captureRequest(
      (dio) => ForecastsApi(
        dio,
      ).getForecastsMap(bbox: '30,59,31,60', at: '2026-08-09T10:00:00Z'),
    );

    expect(request.path, '/forecasts');
    expect(request.queryParameters['is_active'], isTrue);
    expect(request.queryParameters, isNot(contains('latest_model_only')));
  });
}

Future<RequestOptions> _captureRequest(
  Future<List<Map<String, dynamic>>> Function(Dio dio) execute,
) async {
  late RequestOptions captured;
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(requestOptions: options, data: const []));
        },
      ),
    );

  await execute(dio);
  return captured;
}
