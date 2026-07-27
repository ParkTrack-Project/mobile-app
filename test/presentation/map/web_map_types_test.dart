import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/web_map_types.dart';

void main() {
  test('web map controller forwards camera and retry controls', () {
    final controller = WebMapController();
    controller.camera = const WebMapCamera(
      latitude: 61.7,
      longitude: 34.3,
      zoom: 14,
      west: 34,
      south: 61,
      east: 35,
      north: 62,
    );
    double? zoom;
    (double, double, double)? move;
    var retries = 0;
    controller.zoomHandler = (value) => zoom = value;
    controller.moveHandler = (lat, lon, value) => move = (lat, lon, value);
    controller.retryHandler = () => retries++;

    controller.zoomBy(1);
    controller.move(60, 30, 16);
    controller.retry();

    expect(zoom, 15);
    expect(move, (60, 30, 16));
    expect(retries, 1);
  });
}
