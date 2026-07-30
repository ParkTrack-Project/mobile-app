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
    (double, double, double, double, double, double, double, double, double)?
    fit;
    (double, double, double, double, double, double, double, double)? follow;
    var retries = 0;
    controller.zoomHandler = (value) => zoom = value;
    controller.moveHandler = (lat, lon, value) => move = (lat, lon, value);
    controller.fitBoundsWithInsetsHandler =
        (south, west, north, east, azimuth, top, right, bottom, left) {
          fit = (south, west, north, east, azimuth, top, right, bottom, left);
        };
    controller.followHandler =
        (lat, lon, zoom, azimuth, top, right, bottom, left) {
          follow = (lat, lon, zoom, azimuth, top, right, bottom, left);
        };
    controller.retryHandler = () => retries++;

    controller.zoomBy(1);
    controller.move(60, 30, 16);
    controller.fitBounds(
      60,
      30,
      62,
      35,
      azimuth: 45,
      top: 1,
      right: 2,
      bottom: 3,
      left: 4,
    );
    controller.follow(61, 34, 17, 90, top: 1, right: 2, bottom: 3, left: 4);
    controller.retry();

    expect(zoom, 15);
    expect(move, (60, 30, 16));
    expect(fit, (60, 30, 62, 35, 45, 1, 2, 3, 4));
    expect(follow, (61, 34, 17, 90, 1, 2, 3, 4));
    expect(retries, 1);
    expect(controller.camera!.cameraUpdateFinished, isTrue);
    expect(controller.camera!.userGesture, isFalse);
  });
}
