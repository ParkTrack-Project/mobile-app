class WebMapCamera {
  const WebMapCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    this.azimuth = 0,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double west;
  final double south;
  final double east;
  final double north;
  final double azimuth;
}

class WebMapController {
  WebMapCamera? camera;
  void Function(double latitude, double longitude, double zoom)? moveHandler;
  void Function(double zoom)? zoomHandler;
  void Function(double south, double west, double north, double east)?
  fitBoundsHandler;
  void Function(
    double south,
    double west,
    double north,
    double east,
    double top,
    double right,
    double bottom,
    double left,
  )?
  fitBoundsWithInsetsHandler;
  void Function(
    double latitude,
    double longitude,
    double zoom,
    double top,
    double right,
    double bottom,
    double left,
  )?
  focusHandler;
  void Function()? resetNorthHandler;
  void Function()? retryHandler;

  bool get isReady => camera != null;

  void move(double latitude, double longitude, double zoom) =>
      moveHandler?.call(latitude, longitude, zoom);

  void zoomBy(double delta) {
    final current = camera;
    if (current != null) zoomHandler?.call(current.zoom + delta);
  }

  void fitBounds(
    double south,
    double west,
    double north,
    double east, {
    double top = 0,
    double right = 0,
    double bottom = 0,
    double left = 0,
  }) {
    final withInsets = fitBoundsWithInsetsHandler;
    if (withInsets != null) {
      withInsets(south, west, north, east, top, right, bottom, left);
    } else {
      fitBoundsHandler?.call(south, west, north, east);
    }
  }

  void focus(
    double latitude,
    double longitude,
    double zoom, {
    double top = 0,
    double right = 0,
    double bottom = 0,
    double left = 0,
  }) => focusHandler?.call(latitude, longitude, zoom, top, right, bottom, left);

  void retry() => retryHandler?.call();

  void resetNorth() => resetNorthHandler?.call();

  void clear() {
    camera = null;
    moveHandler = null;
    zoomHandler = null;
    fitBoundsHandler = null;
    fitBoundsWithInsetsHandler = null;
    focusHandler = null;
    resetNorthHandler = null;
    retryHandler = null;
  }
}
