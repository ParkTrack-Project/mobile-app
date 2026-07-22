class WebMapCamera {
  const WebMapCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double west;
  final double south;
  final double east;
  final double north;
}

class WebMapController {
  WebMapCamera? camera;
  void Function(double latitude, double longitude, double zoom)? moveHandler;
  void Function(double zoom)? zoomHandler;
  void Function()? retryHandler;

  bool get isReady => camera != null;

  void move(double latitude, double longitude, double zoom) =>
      moveHandler?.call(latitude, longitude, zoom);

  void zoomBy(double delta) {
    final current = camera;
    if (current != null) zoomHandler?.call(current.zoom + delta);
  }

  void retry() => retryHandler?.call();

  void clear() {
    camera = null;
    moveHandler = null;
    zoomHandler = null;
    retryHandler = null;
  }
}
