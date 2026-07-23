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
  void Function()? resetNorthHandler;
  void Function()? retryHandler;

  bool get isReady => camera != null;

  void move(double latitude, double longitude, double zoom) =>
      moveHandler?.call(latitude, longitude, zoom);

  void zoomBy(double delta) {
    final current = camera;
    if (current != null) zoomHandler?.call(current.zoom + delta);
  }

  void fitBounds(double south, double west, double north, double east) =>
      fitBoundsHandler?.call(south, west, north, east);

  void resetNorth() => resetNorthHandler?.call();

  void retry() => retryHandler?.call();

  void clear() {
    camera = null;
    moveHandler = null;
    zoomHandler = null;
    fitBoundsHandler = null;
    resetNorthHandler = null;
    retryHandler = null;
  }
}
