import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/constants.dart';

final Map<ParkingClusterBitmapKey, Future<Uint8List>> _clusterBitmapCache = {};

const double parkingCounterDimmedOpacity = 0.64;
const double parkingMarkerScaleFactor = 1.3;
const double parkingClusterScaleFactor = parkingMarkerScaleFactor * 0.97;
const double parkingClusterFontScaleFactor = 0.97;
const double parkingClusterMergePx = 22;
const double parkingClusterZoomStep = 0.5;
const double parkingZoneBadgeMinZoom = 14;
const double parkingSelectedZoneZoom = 17;
const double parkingMapMaxZoom = 21;
const double parkingClusterExpansionSearchStep = 0.25;
const double parkingClusterIconScale = 1;
const int _dimmedFillAlpha = 0x66;
const int _dimmedStrokeAlpha = 0xB3;

typedef ParkingClusterBitmapKey = ({
  int totalFree,
  int clusterSize,
  int color,
  int textColor,
});

@immutable
class ParkingCluster {
  const ParkingCluster({
    required this.key,
    required this.center,
    required this.totalFree,
    required this.zoneIds,
  });

  final String key;
  final Point center;
  final int totalFree;
  final Set<int> zoneIds;

  int get zoneCount => zoneIds.length;
}

@immutable
class ParkingClusteringResult {
  const ParkingClusteringResult({
    required this.zoom,
    required this.clusters,
    required this.singletonIds,
  });

  final double zoom;
  final List<ParkingCluster> clusters;
  final Set<int> singletonIds;
}

class _ParkingClusterPoint {
  const _ParkingClusterPoint({
    required this.zone,
    required this.center,
    required this.pixel,
  });

  final Zone zone;
  final Point center;
  final Offset pixel;

  int get free => zone.isActive ? math.max(0, zone.freeCount) : 0;
}

class ParkingZoneColors {
  const ParkingZoneColors({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  ParkingZoneColors dimmed() => ParkingZoneColors(
    fill: fill.withAlpha(_dimmedFillAlpha),
    stroke: stroke.withAlpha(_dimmedStrokeAlpha),
  );
}

class ParkingMarkerState {
  const ParkingMarkerState({
    required this.activeIds,
    required this.mutedResultIds,
    required this.contextIds,
  });

  final Set<int> activeIds;
  final Set<int> mutedResultIds;
  final Set<int> contextIds;
}

ParkingMarkerState resolveParkingMarkerState({
  required Set<int> allIds,
  required Set<int> resultIds,
  int? selectedId,
}) {
  if (selectedId != null) {
    final selectedIds = allIds.intersection({selectedId});
    return ParkingMarkerState(
      activeIds: Set.unmodifiable(selectedIds),
      mutedResultIds: Set.unmodifiable(
        resultIds.intersection(allIds).difference(selectedIds),
      ),
      contextIds: Set.unmodifiable(
        allIds.difference(selectedIds).difference(resultIds),
      ),
    );
  }
  if (resultIds.isEmpty) {
    return ParkingMarkerState(
      activeIds: Set.unmodifiable(allIds),
      mutedResultIds: const {},
      contextIds: const {},
    );
  }
  return ParkingMarkerState(
    activeIds: Set.unmodifiable(resultIds),
    mutedResultIds: const {},
    contextIds: Set.unmodifiable(allIds.difference(resultIds)),
  );
}

Future<Uint8List> _cachedClusterBitmap(
  int totalFree,
  int clusterSize,
  Color color,
  Color textColor,
) {
  final key = (
    totalFree: totalFree,
    clusterSize: clusterSize,
    color: color.toARGB32(),
    textColor: textColor.toARGB32(),
  );
  if (_clusterBitmapCache.length > 128) _clusterBitmapCache.clear();
  return _clusterBitmapCache.putIfAbsent(
    key,
    () => buildClusterBitmap(totalFree, clusterSize, color, textColor),
  );
}

double parkingClusterZoomBucket(double zoom) =>
    (zoom / parkingClusterZoomStep).floor() * parkingClusterZoomStep;

double parkingClusterFreeCap(double zoom) {
  if (zoom < 7) return 1400;
  if (zoom < 10) return 350;
  if (zoom < 13) return 150;
  return double.infinity;
}

ParkingClusteringResult clusterParkingZones(
  List<Zone> zones,
  double zoom, {
  bool quantizeZoom = true,
}) {
  final effectiveZoom = quantizeZoom ? parkingClusterZoomBucket(zoom) : zoom;
  final points = zones
      .where(isParkingZoneRenderable)
      .map((zone) {
        final center = centroid(zone.geometry);
        return _ParkingClusterPoint(
          zone: zone,
          center: center,
          pixel: _worldPixel(center, effectiveZoom),
        );
      })
      .toList(growable: false);
  if (points.isEmpty) {
    return ParkingClusteringResult(
      zoom: effectiveZoom,
      clusters: const [],
      singletonIds: const {},
    );
  }

  final connectedGroups = _connectedParkingGroups(points);
  final cap = parkingClusterFreeCap(effectiveZoom);
  final splitGroups = <List<_ParkingClusterPoint>>[];
  for (final group in connectedGroups) {
    splitGroups.addAll(_splitParkingGroupByCap(group, cap));
  }

  final singletonIds = <int>{};
  var aggregateGroups = <List<_ParkingClusterPoint>>[];
  for (final group in splitGroups) {
    if (group.length == 1) {
      singletonIds.add(group.single.zone.zoneId);
    } else {
      aggregateGroups.add(group);
    }
  }
  aggregateGroups = _mergeOverlappingParkingGroups(
    aggregateGroups,
    effectiveZoom,
  );

  final clusters = aggregateGroups.map(_parkingClusterFromPoints).toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return ParkingClusteringResult(
    zoom: effectiveZoom,
    clusters: List.unmodifiable(clusters),
    singletonIds: Set.unmodifiable(singletonIds),
  );
}

List<List<_ParkingClusterPoint>> _connectedParkingGroups(
  List<_ParkingClusterPoint> points,
) {
  final parents = List<int>.generate(points.length, (index) => index);
  final cells = <(int, int), List<int>>{};

  int root(int index) {
    while (parents[index] != index) {
      parents[index] = parents[parents[index]];
      index = parents[index];
    }
    return index;
  }

  void union(int left, int right) {
    final leftRoot = root(left);
    final rightRoot = root(right);
    if (leftRoot != rightRoot) parents[rightRoot] = leftRoot;
  }

  for (var index = 0; index < points.length; index++) {
    final pixel = points[index].pixel;
    final cellX = (pixel.dx / parkingClusterMergePx).floor();
    final cellY = (pixel.dy / parkingClusterMergePx).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final other in cells[(cellX + dx, cellY + dy)] ?? const <int>[]) {
          if ((points[other].pixel - pixel).distance <= parkingClusterMergePx) {
            union(index, other);
          }
        }
      }
    }
    cells.putIfAbsent((cellX, cellY), () => <int>[]).add(index);
  }

  final groups = <int, List<_ParkingClusterPoint>>{};
  for (var index = 0; index < points.length; index++) {
    groups.putIfAbsent(root(index), () => []).add(points[index]);
  }
  return groups.values.toList(growable: false);
}

List<List<_ParkingClusterPoint>> _splitParkingGroupByCap(
  List<_ParkingClusterPoint> points,
  double cap,
) {
  final totalFree = points.fold<int>(0, (sum, point) => sum + point.free);
  if (points.length <= 1 || totalFree <= cap) return [points];

  final minX = points.map((point) => point.pixel.dx).reduce(math.min);
  final maxX = points.map((point) => point.pixel.dx).reduce(math.max);
  final minY = points.map((point) => point.pixel.dy).reduce(math.min);
  final maxY = points.map((point) => point.pixel.dy).reduce(math.max);
  final splitOnX = maxX - minX >= maxY - minY;
  final sorted = [...points]
    ..sort((left, right) {
      final comparison = splitOnX
          ? left.pixel.dx.compareTo(right.pixel.dx)
          : left.pixel.dy.compareTo(right.pixel.dy);
      return comparison != 0
          ? comparison
          : left.zone.zoneId.compareTo(right.zone.zoneId);
    });
  final midpoint = sorted.length ~/ 2;
  return [
    ..._splitParkingGroupByCap(sorted.sublist(0, midpoint), cap),
    ..._splitParkingGroupByCap(sorted.sublist(midpoint), cap),
  ];
}

List<List<_ParkingClusterPoint>> _mergeOverlappingParkingGroups(
  List<List<_ParkingClusterPoint>> groups,
  double zoom,
) {
  var current = groups;
  while (current.length > 1) {
    final parents = List<int>.generate(current.length, (index) => index);
    final centers = current
        .map((group) => _worldPixel(_meanParkingCenter(group), zoom))
        .toList(growable: false);

    int root(int index) {
      while (parents[index] != index) {
        parents[index] = parents[parents[index]];
        index = parents[index];
      }
      return index;
    }

    var merged = false;
    for (var left = 0; left < current.length; left++) {
      for (var right = left + 1; right < current.length; right++) {
        final minimumDistance =
            parkingClusterSize(current[left].length) / 2 +
            2 +
            parkingClusterSize(current[right].length) / 2 +
            2;
        if ((centers[left] - centers[right]).distance < minimumDistance) {
          final leftRoot = root(left);
          final rightRoot = root(right);
          if (leftRoot != rightRoot) {
            parents[rightRoot] = leftRoot;
            merged = true;
          }
        }
      }
    }
    if (!merged) return current;

    final next = <int, List<_ParkingClusterPoint>>{};
    for (var index = 0; index < current.length; index++) {
      next.putIfAbsent(root(index), () => []).addAll(current[index]);
    }
    current = next.values.toList(growable: false);
  }
  return current;
}

Point _meanParkingCenter(List<_ParkingClusterPoint> points) => Point(
  latitude:
      points.fold<double>(0, (sum, point) => sum + point.center.latitude) /
      points.length,
  longitude:
      points.fold<double>(0, (sum, point) => sum + point.center.longitude) /
      points.length,
);

ParkingCluster _parkingClusterFromPoints(List<_ParkingClusterPoint> points) {
  final ids = points.map((point) => point.zone.zoneId).toList()..sort();
  return ParkingCluster(
    key: ids.join('-'),
    center: _meanParkingCenter(points),
    totalFree: points.fold<int>(0, (sum, point) => sum + point.free),
    zoneIds: Set.unmodifiable(ids),
  );
}

List<MapObject> buildZoneMapObjects({
  required List<Zone> zones,
  required void Function(Zone) onTap,
  Set<int>? tappableIds,
  Set<int> resultIds = const {},
  int? selectedId,
  Brightness brightness = Brightness.light,
}) {
  final result = <MapObject>[];
  final markerState = resolveParkingMarkerState(
    allIds: zones.map((zone) => zone.zoneId).toSet(),
    resultIds: resultIds,
    selectedId: selectedId,
  );
  for (final zone in zones) {
    if (_isDegenerate(zone.geometry)) continue;
    final colors = parkingZoneColors(zone, brightness: brightness);
    final isSelected = selectedId == zone.zoneId;
    final displayedColors = markerState.activeIds.contains(zone.zoneId)
        ? colors
        : colors.dimmed();
    final zoneOnTap = tappableIds == null || tappableIds.contains(zone.zoneId)
        ? onTap
        : null;
    if (zone.zoneType == ZoneType.parallel) {
      result.add(
        _buildParallelLine(
          zone,
          displayedColors,
          zoneOnTap,
          highlighted: isSelected,
        ),
      );
    } else {
      result.add(
        _buildPolygon(
          zone,
          displayedColors,
          zoneOnTap,
          highlighted: isSelected,
        ),
      );
    }
  }
  return result;
}

List<MapObject> buildHighlightZone(
  List<Zone> zones,
  int zoneId, {
  Brightness brightness = Brightness.light,
}) {
  final matches = zones.where(
    (z) => z.zoneId == zoneId && !_isDegenerate(z.geometry),
  );
  if (matches.isEmpty) return [];
  final zone = matches.first;
  final colors = parkingZoneColors(zone, brightness: brightness);
  if (zone.zoneType == ZoneType.parallel) {
    final points = zone.geometry;
    if (points.length < 4) return [];
    final len01 = _distance(points[0], points[1]);
    final len12 = _distance(points[1], points[2]);
    final Point mid1, mid2;
    if (len01 <= len12) {
      mid1 = _midpoint(points[0], points[1]);
      mid2 = _midpoint(points[2], points[3]);
    } else {
      mid1 = _midpoint(points[1], points[2]);
      mid2 = _midpoint(points[3], points[0]);
    }
    return [
      PolylineMapObject(
        mapId: MapObjectId('zone_highlight_${zone.zoneId}'),
        polyline: Polyline(points: [mid1, mid2]),
        strokeColor: colors.stroke,
        strokeWidth: 8,
      ),
    ];
  } else {
    return [
      PolygonMapObject(
        mapId: MapObjectId('zone_highlight_${zone.zoneId}'),
        polygon: Polygon(
          outerRing: LinearRing(points: zone.geometry),
          innerRings: [],
        ),
        fillColor: colors.fill,
        strokeColor: colors.stroke,
        strokeWidth: 3,
      ),
    ];
  }
}

List<MapObject> buildZoneLabels({
  required List<Zone> zones,
  required ParkingClusteringResult clustering,
  required double zoom,
  required Map<int, Uint8List> bitmapCache,
  required Map<ParkingClusterBitmapKey, Uint8List> clusterBitmapCache,
  required Map<int, Zone> zonesById,
  Set<int> resultIds = const {},
  int? selectedId,
  void Function(ParkingCluster)? onClusterTap,
  void Function(Zone)? onZoneTap,
  Brightness brightness = Brightness.light,
}) {
  final result = <MapObject>[];
  if (zoom >= parkingZoneBadgeMinZoom) {
    result.addAll(
      zones
          .where(
            (zone) =>
                clustering.singletonIds.contains(zone.zoneId) &&
                !_isDegenerate(zone.geometry) &&
                bitmapCache.containsKey(zone.zoneId),
          )
          .map(
            (zone) => PlacemarkMapObject(
              mapId: MapObjectId('zone_label_${zone.zoneId}'),
              point: centroid(zone.geometry),
              opacity: _zoneOpacity(zone.zoneId, resultIds, selectedId),
              icon: PlacemarkIcon.single(
                PlacemarkIconStyle(
                  image: BitmapDescriptor.fromBytes(bitmapCache[zone.zoneId]!),
                  scale: 1.0,
                  zIndex: zone.zoneId == selectedId
                      ? 20
                      : resultIds.contains(zone.zoneId)
                      ? 10
                      : 0,
                ),
              ),
              onTap: onZoneTap != null ? (_, _) => onZoneTap(zone) : null,
            ),
          ),
    );
  }
  for (final cluster in clustering.clusters) {
    final zonesInCluster = cluster.zoneIds
        .map((id) => zonesById[id])
        .whereType<Zone>()
        .toList(growable: false);
    if (zonesInCluster.length < 2) continue;
    final opacity = cluster.zoneIds.contains(selectedId)
        ? 1.0
        : selectedId != null
        ? parkingCounterDimmedOpacity
        : resultIds.isNotEmpty &&
              !cluster.zoneIds.any((zoneId) => resultIds.contains(zoneId))
        ? parkingCounterDimmedOpacity
        : 1.0;
    final key = parkingClusterBitmapKey(cluster, brightness: brightness);
    final bytes = clusterBitmapCache[key];
    if (bytes == null) continue;
    result.add(
      PlacemarkMapObject(
        mapId: MapObjectId('zone_cluster_${cluster.key}'),
        point: cluster.center,
        opacity: opacity,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(bytes),
            anchor: const Offset(0.5, 0.5),
            scale: parkingClusterIconScale,
            zIndex: 30,
          ),
        ),
        onTap: onClusterTap == null ? null : (_, _) => onClusterTap(cluster),
      ),
    );
  }
  return result;
}

ParkingClusterBitmapKey parkingClusterBitmapKey(
  ParkingCluster cluster, {
  Brightness brightness = Brightness.light,
}) {
  final color = parkingClusterColor(cluster.totalFree, brightness: brightness);
  final textColor = brightness == Brightness.dark
      ? const Color(0xFF09090B)
      : Colors.white;
  return (
    totalFree: cluster.totalFree,
    clusterSize: cluster.zoneCount,
    color: color.toARGB32(),
    textColor: textColor.toARGB32(),
  );
}

Future<Uint8List> buildParkingClusterBitmap(
  ParkingCluster cluster, {
  Brightness brightness = Brightness.light,
}) {
  final key = parkingClusterBitmapKey(cluster, brightness: brightness);
  return _cachedClusterBitmap(
    key.totalFree,
    key.clusterSize,
    Color(key.color),
    Color(key.textColor),
  );
}

Future<Uint8List> buildCountBitmap(
  int? count,
  Color color, {
  Color textColor = Colors.white,
}) async {
  const height = 40.0 * parkingMarkerScaleFactor;
  final label = count == null ? '' : '$count';
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: textColor,
        fontSize: 24 * parkingMarkerScaleFactor,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = math.max(
    height,
    textPainter.width + 24 * parkingMarkerScaleFactor,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(height / 2),
    ),
    Paint()..color = color,
  );
  if (label.isNotEmpty) {
    textPainter.paint(
      canvas,
      Offset(
        (width - textPainter.width) / 2,
        (height - textPainter.height) / 2,
      ),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.ceil(), height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> buildClusterBitmap(
  int totalFree,
  int clusterSize,
  Color color,
  Color textColor,
) async {
  final logicalSize = parkingClusterSize(clusterSize);
  final size = logicalSize * 2;
  final center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(center, size / 2 - 4, Paint()..color = color);
  canvas.drawCircle(
    center,
    size / 2 - 3,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final label = '$totalFree';
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: textColor,
        fontSize: parkingClusterFontSize(clusterSize) * 2,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: size - 12);
  textPainter.paint(
    canvas,
    Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

bool _isDegenerate(List<Point> points) {
  if (points.length < 3) return true;
  final lat0 = points.first.latitude;
  final lon0 = points.first.longitude;
  return points.every((p) => p.latitude == lat0 && p.longitude == lon0);
}

bool isParkingZoneRenderable(Zone zone) => !_isDegenerate(zone.geometry);

ParkingZoneColors parkingZoneColors(
  Zone zone, {
  Brightness brightness = Brightness.light,
}) {
  final isDark = brightness == Brightness.dark;
  if (!zone.isActive) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xD9E4E4E7),
            stroke: Color(0xFFD4D4D8),
          )
        : const ParkingZoneColors(
            fill: Color(0x8C9CA3AF),
            stroke: Color(0xFF4B5563),
          );
  }
  if (zone.freeCount == 0) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xE6FF5252),
            stroke: Color(0xFFFF5252),
          )
        : const ParkingZoneColors(
            fill: Color(0x96D81616),
            stroke: Color(0xFFCD2B2B),
          );
  }
  if (zone.freeCount == 1) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xEBFFC107),
            stroke: Color(0xFFFFC107),
          )
        : const ParkingZoneColors(
            fill: Color(0x96F5AB0B),
            stroke: Color(0xFFB48409),
          );
  }
  if (zone.confidence >= kConfidenceThreshold) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xEB00E676),
            stroke: Color(0xFF00E676),
          )
        : const ParkingZoneColors(
            fill: Color(0xAA16A34A),
            stroke: Color(0xFF155E2A),
          );
  }
  return isDark
      ? const ParkingZoneColors(
          fill: Color(0xE04ADE80),
          stroke: Color(0xFF4ADE80),
        )
      : const ParkingZoneColors(
          fill: Color(0x9686EFAC),
          stroke: Color(0xFF2D8714),
        );
}

Color zoneColor(Zone zone, {Brightness brightness = Brightness.light}) =>
    parkingZoneColors(zone, brightness: brightness).stroke;

Color parkingClusterColor(
  int freeCount, {
  Brightness brightness = Brightness.light,
}) {
  if (brightness == Brightness.dark) {
    if (freeCount == 0) return const Color(0xFFFF5252);
    if (freeCount <= 2) return const Color(0xFFFFC107);
    return const Color(0xFF00E676);
  }
  if (freeCount == 0) return const Color(0xFFCD2B2B);
  if (freeCount <= 2) return const Color(0xFFB48409);
  return const Color(0xFF155E2A);
}

double parkingClusterSize(int zoneCount) =>
    math.min(28 + (zoneCount ~/ 4) * 4, 44).toDouble() *
    parkingClusterScaleFactor;

double parkingClusterFontSize(int zoneCount) =>
    (parkingClusterSize(zoneCount) >= 38 * parkingClusterScaleFactor
        ? 19
        : 17) *
    parkingClusterFontScaleFactor;

double parkingClusterExpansionZoom(
  List<Zone> zones,
  Set<int> clusterZoneIds,
  double currentZoom, {
  double maxZoom = parkingMapMaxZoom,
}) {
  final firstZoom =
      parkingClusterZoomBucket(currentZoom) + parkingClusterZoomStep;
  if (clusterZoneIds.length < 2) {
    return math.min(maxZoom, firstZoom);
  }
  for (var zoom = firstZoom; zoom <= maxZoom; zoom += parkingClusterZoomStep) {
    final result = clusterParkingZones(zones, zoom);
    final remainsOneCluster = result.clusters.any(
      (cluster) =>
          clusterZoneIds.every((zoneId) => cluster.zoneIds.contains(zoneId)),
    );
    final hasHiddenSingleton =
        zoom < parkingZoneBadgeMinZoom &&
        clusterZoneIds.any(result.singletonIds.contains);
    if (!remainsOneCluster && !hasHiddenSingleton) {
      return zoom;
    }
  }
  return maxZoom;
}

double parkingIsolationZoom(
  Point selected,
  Iterable<Point> others, {
  required double currentZoom,
  double minimumZoom = parkingSelectedZoneZoom,
  double maximumZoom = parkingMapMaxZoom,
  double radius = parkingClusterMergePx,
}) {
  var zoom = math.max(minimumZoom, currentZoom);
  final otherPoints = others.toList(growable: false);
  while (zoom <= maximumZoom) {
    final selectedPixel = _worldPixel(selected, zoom);
    final isolated = otherPoints.every((point) {
      final pixel = _worldPixel(point, zoom);
      return (pixel - selectedPixel).distance > radius;
    });
    if (isolated) return math.min(maximumZoom, zoom);
    zoom += parkingClusterExpansionSearchStep;
  }
  return maximumZoom;
}

double parkingZoneIsolationZoom(
  List<Zone> zones,
  int selectedZoneId, {
  required double currentZoom,
  double minimumZoom = parkingSelectedZoneZoom,
  double maximumZoom = parkingMapMaxZoom,
}) {
  final selectedIsRenderable = zones.any(
    (zone) => zone.zoneId == selectedZoneId && isParkingZoneRenderable(zone),
  );
  if (!selectedIsRenderable) {
    return math.max(minimumZoom, currentZoom).clamp(0, maximumZoom).toDouble();
  }

  var zoom = math
      .max(minimumZoom, currentZoom)
      .clamp(0, maximumZoom)
      .toDouble();
  while (zoom <= maximumZoom) {
    final clustering = clusterParkingZones(zones, zoom);
    if (clustering.singletonIds.contains(selectedZoneId) &&
        !clustering.clusters.any(
          (cluster) => cluster.zoneIds.contains(selectedZoneId),
        )) {
      return zoom.toDouble();
    }
    zoom = parkingClusterZoomBucket(zoom) + parkingClusterZoomStep;
  }
  return maximumZoom;
}

Offset _worldPixel(Point point, double zoom) {
  final scale = 256 * math.pow(2, zoom);
  final latitude = point.latitude.clamp(-85.05112878, 85.05112878);
  final sinLatitude = math.sin(latitude * math.pi / 180);
  return Offset(
    ((point.longitude + 180) / 360) * scale,
    (0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        scale,
  );
}

MapObject _buildPolygon(
  Zone zone,
  ParkingZoneColors colors,
  void Function(Zone)? onTap, {
  bool highlighted = false,
}) {
  return PolygonMapObject(
    mapId: MapObjectId('zone_polygon_${zone.zoneId}'),
    polygon: Polygon(
      outerRing: LinearRing(points: zone.geometry),
      innerRings: [],
    ),
    fillColor: colors.fill,
    strokeColor: colors.stroke,
    strokeWidth: highlighted ? 3 : 1,
    onTap: onTap == null ? null : (_, _) => onTap(zone),
  );
}

MapObject _buildParallelLine(
  Zone zone,
  ParkingZoneColors colors,
  void Function(Zone)? onTap, {
  bool highlighted = false,
}) {
  final points = zone.geometry;
  if (points.length < 4) {
    return _buildPolygon(zone, colors, onTap);
  }

  final len01 = _distance(points[0], points[1]);
  final len12 = _distance(points[1], points[2]);

  final Point mid1, mid2;
  if (len01 <= len12) {
    // стороны 0→1 и 2→3 — короткие (торцы ряда)
    mid1 = _midpoint(points[0], points[1]);
    mid2 = _midpoint(points[2], points[3]);
  } else {
    // стороны 1→2 и 3→0 — короткие (торцы ряда)
    mid1 = _midpoint(points[1], points[2]);
    mid2 = _midpoint(points[3], points[0]);
  }

  return PolylineMapObject(
    mapId: MapObjectId('zone_line_${zone.zoneId}'),
    polyline: Polyline(points: [mid1, mid2]),
    strokeColor: colors.stroke,
    strokeWidth: highlighted ? 8 : 6,
    onTap: onTap == null ? null : (_, _) => onTap(zone),
  );
}

double _zoneOpacity(int zoneId, Set<int> resultIds, int? selectedId) {
  if (selectedId != null) {
    if (zoneId == selectedId) return 1;
    return parkingCounterDimmedOpacity;
  }
  if (resultIds.isNotEmpty && !resultIds.contains(zoneId)) {
    return parkingCounterDimmedOpacity;
  }
  return 1;
}

double _distance(Point a, Point b) {
  final dlat = a.latitude - b.latitude;
  final dlon = a.longitude - b.longitude;
  return math.sqrt(dlat * dlat + dlon * dlon);
}

Point _midpoint(Point a, Point b) => Point(
  latitude: (a.latitude + b.latitude) / 2,
  longitude: (a.longitude + b.longitude) / 2,
);

Point centroid(List<Point> points) {
  final pts =
      points.length > 1 &&
          points.first.latitude == points.last.latitude &&
          points.first.longitude == points.last.longitude
      ? points.sublist(0, points.length - 1)
      : points;
  final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
  final lon = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  return Point(latitude: lat, longitude: lon);
}
