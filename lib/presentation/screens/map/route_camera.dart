import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

class RouteMapBounds {
  const RouteMapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  BoundingBox get boundingBox => BoundingBox(
    southWest: Point(latitude: south, longitude: west),
    northEast: Point(latitude: north, longitude: east),
  );
}

class RouteCameraPlan {
  const RouteCameraPlan({
    required this.center,
    required this.zoom,
    required this.azimuth,
  });

  final Point center;
  final double zoom;
  final double azimuth;
}

@visibleForTesting
Offset projectRoutePointToViewport(
  Point point,
  RouteCameraPlan plan, {
  required Size viewport,
}) {
  final center = _projectMercator(plan.center);
  final localPoint = _projectMercator(
    Point(
      latitude: point.latitude,
      longitude:
          plan.center.longitude +
          _longitudeDelta(plan.center.longitude, point.longitude),
    ),
  );
  final radians = _radians(-plan.azimuth);
  final cosine = math.cos(radians);
  final sine = math.sin(radians);
  final delta = localPoint - center;
  final rotated = Offset(
    delta.dx * cosine - delta.dy * sine,
    delta.dx * sine + delta.dy * cosine,
  );
  final scale = math.pow(2, plan.zoom).toDouble();
  return Offset(
    viewport.width / 2 + rotated.dx * scale,
    viewport.height / 2 + rotated.dy * scale,
  );
}

RouteMapBounds? calculateRouteBounds(List<Point>? points) {
  final valid = validRoutePoints(points);
  if (valid.length < 2) return null;

  var south = valid.first.latitude;
  var north = south;
  var west = valid.first.longitude;
  var east = west;
  for (final point in valid.skip(1)) {
    south = math.min(south, point.latitude);
    north = math.max(north, point.latitude);
    west = math.min(west, point.longitude);
    east = math.max(east, point.longitude);
  }
  if ((north - south).abs() < 0.0005) {
    south -= 0.00025;
    north += 0.00025;
  }
  if ((east - west).abs() < 0.0005) {
    west -= 0.00025;
    east += 0.00025;
  }
  return RouteMapBounds(south: south, west: west, north: north, east: east);
}

double? calculateRouteAzimuth(List<Point>? points) {
  final valid = validRoutePoints(points);
  if (valid.length < 2) return null;
  final start = valid.first;
  final finish = valid.last;
  if ((start.latitude - finish.latitude).abs() < 1e-12 &&
      _longitudeDelta(start.longitude, finish.longitude).abs() < 1e-12) {
    return null;
  }

  final startLatitude = _radians(start.latitude);
  final finishLatitude = _radians(finish.latitude);
  final longitudeDelta = _radians(
    _longitudeDelta(start.longitude, finish.longitude),
  );
  final y = math.sin(longitudeDelta) * math.cos(finishLatitude);
  final x =
      math.cos(startLatitude) * math.sin(finishLatitude) -
      math.sin(startLatitude) *
          math.cos(finishLatitude) *
          math.cos(longitudeDelta);
  return (_degrees(math.atan2(y, x)) + 360) % 360;
}

List<Point> validRoutePoints(List<Point>? points) =>
    points
        ?.where(
          (point) =>
              point.latitude.isFinite &&
              point.longitude.isFinite &&
              point.latitude >= -90 &&
              point.latitude <= 90 &&
              point.longitude >= -180 &&
              point.longitude <= 180,
        )
        .toList(growable: false) ??
    const [];

double _longitudeDelta(double from, double to) =>
    ((to - from + 540) % 360) - 180;

double _radians(double degrees) => degrees * math.pi / 180;

double _degrees(double radians) => radians * 180 / math.pi;

RouteCameraPlan? calculateRouteCameraPlan(
  List<Point>? points, {
  required Size viewport,
  required EdgeInsets margins,
  double minimumZoom = 3,
  double maximumZoom = 21,
}) {
  final valid = validRoutePoints(points);
  final azimuth = calculateRouteAzimuth(valid);
  if (valid.length < 2 || azimuth == null) return null;

  final radians = _radians(-azimuth);
  final cosine = math.cos(radians);
  final sine = math.sin(radians);
  final unwrapped = <Point>[];
  var previousLongitude = valid.first.longitude;
  var unwrappedLongitude = previousLongitude;
  for (final point in valid) {
    if (unwrapped.isNotEmpty) {
      unwrappedLongitude += _longitudeDelta(previousLongitude, point.longitude);
      previousLongitude = point.longitude;
    }
    unwrapped.add(
      Point(latitude: point.latitude, longitude: unwrappedLongitude),
    );
  }
  final projected = unwrapped
      .map(_projectMercator)
      .map((point) {
        return Offset(
          point.dx * cosine - point.dy * sine,
          point.dx * sine + point.dy * cosine,
        );
      })
      .toList(growable: false);
  final minX = projected.map((point) => point.dx).reduce(math.min);
  final maxX = projected.map((point) => point.dx).reduce(math.max);
  final minY = projected.map((point) => point.dy).reduce(math.min);
  final maxY = projected.map((point) => point.dy).reduce(math.max);
  final availableWidth = math.max(
    1.0,
    viewport.width - margins.horizontal - 16,
  );
  final availableHeight = math.max(
    1.0,
    viewport.height - margins.vertical - 16,
  );
  final spanX = math.max(1e-9, maxX - minX);
  final spanY = math.max(1e-9, maxY - minY);
  final zoomX = math.log(availableWidth / spanX) / math.ln2;
  final zoomY = math.log(availableHeight / spanY) / math.ln2;
  final zoom = math
      .min(zoomX, zoomY)
      .clamp(minimumZoom, maximumZoom)
      .toDouble();

  final rotatedCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final visibleCenter = Offset(
    margins.left + availableWidth / 2,
    margins.top + availableHeight / 2,
  );
  final viewportCenter = Offset(viewport.width / 2, viewport.height / 2);
  final screenOffset = visibleCenter - viewportCenter;
  final scale = math.pow(2, zoom).toDouble();
  final cameraCenter = rotatedCenter - screenOffset / scale;
  final inverseRadians = -radians;
  final inverseCosine = math.cos(inverseRadians);
  final inverseSine = math.sin(inverseRadians);
  final projectedCenter = Offset(
    cameraCenter.dx * inverseCosine - cameraCenter.dy * inverseSine,
    cameraCenter.dx * inverseSine + cameraCenter.dy * inverseCosine,
  );
  return RouteCameraPlan(
    center: _unprojectMercator(projectedCenter),
    zoom: zoom,
    azimuth: azimuth,
  );
}

Offset _projectMercator(Point point) {
  final latitude = point.latitude.clamp(-85.05112878, 85.05112878);
  final sinLatitude = math.sin(_radians(latitude));
  return Offset(
    ((point.longitude + 180) / 360) * 256,
    (0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        256,
  );
}

Point _unprojectMercator(Offset point) {
  final rawLongitude = point.dx / 256 * 360 - 180;
  final longitude = ((rawLongitude + 180) % 360 + 360) % 360 - 180;
  final mercatorY = 0.5 - point.dy / 256;
  final value = mercatorY * 2 * math.pi;
  final hyperbolicSine = (math.exp(value) - math.exp(-value)) / 2;
  final latitude = _degrees(math.atan(hyperbolicSine));
  return Point(latitude: latitude, longitude: longitude);
}

RouteMapBounds padRouteBoundsForPanel(
  RouteMapBounds bounds, {
  double horizontalFraction = 0.12,
  double topFraction = 0.12,
  double bottomFraction = 0.65,
}) {
  final latitudeSpan = bounds.north - bounds.south;
  final longitudeSpan = bounds.east - bounds.west;
  return RouteMapBounds(
    south: (bounds.south - latitudeSpan * bottomFraction).clamp(-90, 90),
    west: (bounds.west - longitudeSpan * horizontalFraction).clamp(-180, 180),
    north: (bounds.north + latitudeSpan * topFraction).clamp(-90, 90),
    east: (bounds.east + longitudeSpan * horizontalFraction).clamp(-180, 180),
  );
}

RouteMapBounds ensureLocalContextBounds(
  RouteMapBounds bounds, {
  double minimumLatitudeSpan = 0.0012,
  double minimumLongitudeSpan = 0.002,
  double geometryScale = 1.35,
}) {
  final latitudeCenter = (bounds.south + bounds.north) / 2;
  final longitudeCenter = (bounds.west + bounds.east) / 2;
  final latitudeSpan = math.max(
    (bounds.north - bounds.south) * geometryScale,
    minimumLatitudeSpan,
  );
  final longitudeSpan = math.max(
    (bounds.east - bounds.west) * geometryScale,
    minimumLongitudeSpan,
  );
  return RouteMapBounds(
    south: (latitudeCenter - latitudeSpan / 2).clamp(-90, 90),
    west: (longitudeCenter - longitudeSpan / 2).clamp(-180, 180),
    north: (latitudeCenter + latitudeSpan / 2).clamp(-90, 90),
    east: (longitudeCenter + longitudeSpan / 2).clamp(-180, 180),
  );
}

ScreenRect routeFocusRect({
  required Size viewport,
  required EdgeInsets safePadding,
  required double bottomPanelHeight,
  double devicePixelRatio = 1,
}) {
  const horizontalPadding = 32.0;
  const topControlsHeight = 112.0;
  final left = safePadding.left + horizontalPadding;
  final top = safePadding.top + topControlsHeight;
  final right = math.max(left + 1, viewport.width - safePadding.right - 32);
  final bottom = math.max(
    top + 1,
    viewport.height - safePadding.bottom - bottomPanelHeight - 32,
  );
  return ScreenRect(
    topLeft: ScreenPoint(x: left * devicePixelRatio, y: top * devicePixelRatio),
    bottomRight: ScreenPoint(
      x: right * devicePixelRatio,
      y: bottom * devicePixelRatio,
    ),
  );
}

ScreenRect visibleMapFocusRect({
  required Size viewport,
  required EdgeInsets margins,
  double devicePixelRatio = 1,
}) {
  final left = margins.left.clamp(0.0, viewport.width);
  final top = margins.top.clamp(0.0, viewport.height);
  final right = math.max(left + 1, viewport.width - margins.right);
  final bottom = math.max(top + 1, viewport.height - margins.bottom);
  return ScreenRect(
    topLeft: ScreenPoint(x: left * devicePixelRatio, y: top * devicePixelRatio),
    bottomRight: ScreenPoint(
      x: right * devicePixelRatio,
      y: bottom * devicePixelRatio,
    ),
  );
}
