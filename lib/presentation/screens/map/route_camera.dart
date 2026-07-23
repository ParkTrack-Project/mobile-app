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
  final valid = points
      ?.where(
        (point) =>
            point.latitude.isFinite &&
            point.longitude.isFinite &&
            point.latitude >= -90 &&
            point.latitude <= 90 &&
            point.longitude >= -180 &&
            point.longitude <= 180,
      )
      .toList(growable: false);
  if (valid == null || valid.length < 2) return null;

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
  double minimumLatitudeSpan = 0.0025,
  double minimumLongitudeSpan = 0.004,
}) {
  final latitudeCenter = (bounds.south + bounds.north) / 2;
  final longitudeCenter = (bounds.west + bounds.east) / 2;
  final latitudeSpan = math.max(
    bounds.north - bounds.south,
    minimumLatitudeSpan,
  );
  final longitudeSpan = math.max(
    bounds.east - bounds.west,
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
}) {
  const horizontalPadding = 24.0;
  const topControlsHeight = 88.0;
  final left = safePadding.left + horizontalPadding;
  final top = safePadding.top + topControlsHeight;
  final right = math.max(left + 1, viewport.width - safePadding.right - 24);
  final bottom = math.max(
    top + 1,
    viewport.height - safePadding.bottom - bottomPanelHeight - 20,
  );
  return ScreenRect(
    topLeft: ScreenPoint(x: left, y: top),
    bottomRight: ScreenPoint(x: right, y: bottom),
  );
}
