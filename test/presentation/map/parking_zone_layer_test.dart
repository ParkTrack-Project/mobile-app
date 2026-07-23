import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/screens/map/widgets/parking_zone_layer.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

Zone _zone(int id) => Zone(
  zoneId: id,
  zoneType: ZoneType.standard,
  capacity: 10,
  freeCount: 3,
  confidence: 0.9,
  pay: 0,
  geometry: const [
    Point(latitude: 1, longitude: 1),
    Point(latitude: 1, longitude: 2),
    Point(latitude: 2, longitude: 2),
  ],
);

int _alpha(PolygonMapObject object) => object.fillColor.toARGB32() >>> 24;

void main() {
  test('resolves active, muted result, and context marker IDs', () {
    final results = resolveParkingMarkerState(
      allIds: {1, 2, 3, 4},
      resultIds: {1, 2, 3},
      selectedId: 2,
    );

    expect(results.activeIds, {2});
    expect(results.mutedResultIds, {1, 3});
    expect(results.contextIds, {4});
  });

  test('mutes zones outside results and keeps result zones active', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2)],
      resultIds: {1},
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[0]), greaterThan(_alpha(objects[1])));
  });

  test('mutes every zone except the selected result', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2)],
      resultIds: {1, 2},
      selectedId: 2,
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[1]), greaterThan(_alpha(objects[0])));
    expect(objects[1].strokeWidth, 4);
    expect(objects[1].strokeColor, zoneColor(_zone(2)));
  });

  test('mutes result and context zones equally after selection', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2), _zone(3)],
      resultIds: {1, 2},
      selectedId: 2,
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[1]), greaterThan(_alpha(objects[0])));
    expect(_alpha(objects[0]), _alpha(objects[2]));
  });

  test('direct map selection mutes every other zone', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2), _zone(3)],
      selectedId: 2,
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[1]), greaterThan(_alpha(objects[0])));
    expect(_alpha(objects[0]), _alpha(objects[2]));
    expect(objects[1].strokeWidth, objects[0].strokeWidth * 2);
  });

  test('uses a brighter parking palette on the dark map theme', () {
    final light = zoneColor(_zone(1), brightness: Brightness.light);
    final dark = zoneColor(_zone(1), brightness: Brightness.dark);

    expect(dark, isNot(light));
    expect(dark.computeLuminance(), greaterThan(light.computeLuminance()));
  });
}
