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
