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
    (double, double)? zoom;
    (double, double, double)? move;
    (double, double, double, double, double, double, double, double, double)?
    fit;
    (double, double, double, double, double, double, double, double, double)?
    follow;
    (double, double, double, double, double, double, double, double)? camera;
    var retries = 0;
    controller.zoomHandler = (value, duration) => zoom = (value, duration);
    controller.moveHandler = (lat, lon, value) => move = (lat, lon, value);
    controller.fitBoundsWithInsetsHandler =
        (south, west, north, east, azimuth, top, right, bottom, left) {
          fit = (south, west, north, east, azimuth, top, right, bottom, left);
        };
    controller.followHandler =
        (lat, lon, zoom, azimuth, top, right, bottom, left, duration) {
          follow = (
            lat,
            lon,
            zoom,
            azimuth,
            top,
            right,
            bottom,
            left,
            duration,
          );
        };
    controller.cameraHandler =
        (lat, lon, zoom, azimuth, top, right, bottom, left) {
          camera = (lat, lon, zoom, azimuth, top, right, bottom, left);
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
    controller.follow(
      61,
      34,
      17,
      90,
      top: 1,
      right: 2,
      bottom: 3,
      left: 4,
      durationSeconds: 0.18,
    );
    controller.setCamera(62, 35, 15, 45, top: 5, right: 6, bottom: 7, left: 8);
    controller.retry();

    expect(zoom, (15, 0.2));
    expect(move, (60, 30, 16));
    expect(fit, (60, 30, 62, 35, 45, 1, 2, 3, 4));
    expect(follow, (61, 34, 17, 90, 1, 2, 3, 4, 0.18));
    expect(camera, (62, 35, 15, 45, 5, 6, 7, 8));
    expect(retries, 1);
    expect(controller.camera!.cameraUpdateFinished, isTrue);
    expect(controller.camera!.userGesture, isFalse);
  });
}
