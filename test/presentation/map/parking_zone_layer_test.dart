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
    expect(objects[1].strokeWidth, 3);
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
    expect(objects[1].strokeWidth, objects[0].strokeWidth * 3);
  });

  test('uses a brighter parking palette on the dark map theme', () {
    final light = zoneColor(_zone(1), brightness: Brightness.light);
    final dark = zoneColor(_zone(1), brightness: Brightness.dark);

    expect(dark, isNot(light));
    expect(dark.computeLuminance(), greaterThan(light.computeLuminance()));
  });

  test('uses the project palette and exact dimmed geometry alphas', () {
    final active =
        buildZoneMapObjects(zones: [_zone(1)], onTap: (_) {}).single
            as PolygonMapObject;
    final dimmed =
        buildZoneMapObjects(
              zones: [_zone(1), _zone(2)],
              resultIds: {2},
              onTap: (_) {},
            ).first
            as PolygonMapObject;

    expect(active.fillColor, const Color(0xAA16A34A));
    expect(active.strokeColor, const Color(0xFF155E2A));
    expect(dimmed.fillColor.toARGB32() >>> 24, 0x2E);
    expect(dimmed.strokeColor.toARGB32() >>> 24, 0x5C);
  });

  test('matches every light and dark semantic palette color', () {
    final inactive = _zone(1).copyWith(isActive: false);
    final full = _zone(2).copyWith(freeCount: 0);
    final one = _zone(3).copyWith(freeCount: 1);
    final lowConfidence = _zone(4).copyWith(freeCount: 2, confidence: 0.5);
    final highConfidence = _zone(5).copyWith(freeCount: 2, confidence: 0.9);

    expect(
      parkingZoneColors(inactive),
      isA<ParkingZoneColors>()
          .having((value) => value.fill, 'fill', const Color(0x8C9CA3AF))
          .having((value) => value.stroke, 'stroke', const Color(0xFF4B5563)),
    );
    expect(parkingZoneColors(full).fill, const Color(0x96D81616));
    expect(parkingZoneColors(full).stroke, const Color(0xFFCD2B2B));
    expect(parkingZoneColors(one).fill, const Color(0x96F5AB0B));
    expect(parkingZoneColors(one).stroke, const Color(0xFFB48409));
    expect(parkingZoneColors(lowConfidence).fill, const Color(0x9686EFAC));
    expect(parkingZoneColors(lowConfidence).stroke, const Color(0xFF2D8714));
    expect(parkingZoneColors(highConfidence).fill, const Color(0xAA16A34A));
    expect(parkingZoneColors(highConfidence).stroke, const Color(0xFF155E2A));

    expect(
      parkingZoneColors(inactive, brightness: Brightness.dark).fill,
      const Color(0xD9E4E4E7),
    );
    expect(
      parkingZoneColors(full, brightness: Brightness.dark).fill,
      const Color(0xE6FF5252),
    );
    expect(
      parkingZoneColors(one, brightness: Brightness.dark).fill,
      const Color(0xEBFFC107),
    );
    expect(
      parkingZoneColors(lowConfidence, brightness: Brightness.dark).fill,
      const Color(0xE04ADE80),
    );
    expect(
      parkingZoneColors(highConfidence, brightness: Brightness.dark).fill,
      const Color(0xEB00E676),
    );
  });

  test('one cluster tap computes a zoom that splits its points', () {
    final zoom = parkingClusterExpansionZoom(const [
      Point(latitude: 61.7890, longitude: 34.3590),
      Point(latitude: 61.7891, longitude: 34.3591),
      Point(latitude: 61.7940, longitude: 34.3650),
    ], 13);

    expect(zoom, greaterThan(13));
    expect(zoom, lessThanOrEqualTo(21));
  });
}
