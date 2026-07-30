import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/route_camera.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  test('calculates bounds containing the complete route', () {
    final bounds = calculateRouteBounds(const [
      Point(latitude: 61.70, longitude: 34.20),
      Point(latitude: 61.80, longitude: 34.40),
      Point(latitude: 61.75, longitude: 34.30),
    ]);

    expect(bounds, isNotNull);
    expect(bounds!.south, 61.70);
    expect(bounds.north, 61.80);
    expect(bounds.west, 34.20);
    expect(bounds.east, 34.40);
  });

  test('calculates camera azimuth from route start to finish', () {
    expect(
      calculateRouteAzimuth(const [
        Point(latitude: 0, longitude: 0),
        Point(latitude: 1, longitude: 0),
      ]),
      closeTo(0, 1e-10),
    );
    expect(
      calculateRouteAzimuth(const [
        Point(latitude: 0, longitude: 0),
        Point(latitude: 0, longitude: 1),
      ]),
      closeTo(90, 1e-10),
    );
  });

  test('route azimuth uses the short direction across the date line', () {
    expect(
      calculateRouteAzimuth(const [
        Point(latitude: 0, longitude: 179),
        Point(latitude: 0, longitude: -179),
      ]),
      closeTo(90, 1e-10),
    );
  });

  test('route azimuth ignores invalid points and rejects equal endpoints', () {
    expect(
      calculateRouteAzimuth(const [
        Point(latitude: double.nan, longitude: 10),
        Point(latitude: 1, longitude: 1),
        Point(latitude: 1, longitude: 1),
      ]),
      isNull,
    );
  });

  test('builds a rotated web camera plan from the complete route', () {
    final plan = calculateRouteCameraPlan(
      const [
        Point(latitude: 61.78, longitude: 34.34),
        Point(latitude: 61.80, longitude: 34.42),
        Point(latitude: 61.82, longitude: 34.36),
      ],
      viewport: const Size(360, 800),
      margins: const EdgeInsets.fromLTRB(32, 112, 32, 292),
    );

    expect(plan, isNotNull);
    expect(plan!.zoom, inInclusiveRange(3, 21));
    expect(plan.azimuth, inInclusiveRange(0, 360));
    expect(plan.center.latitude, inInclusiveRange(61.78, 61.82));
    expect(plan.center.longitude, inInclusiveRange(34.34, 34.42));
  });

  test('route camera plan keeps date-line routes local', () {
    final plan = calculateRouteCameraPlan(
      const [
        Point(latitude: 0, longitude: 179),
        Point(latitude: 0.2, longitude: -179),
      ],
      viewport: const Size(400, 800),
      margins: const EdgeInsets.fromLTRB(32, 112, 32, 300),
    );

    expect(plan, isNotNull);
    expect(plan!.center.longitude.abs(), greaterThan(170));
    expect(plan.zoom, greaterThan(3));
  });

  test('pads route bounds to keep the route above the preview panel', () {
    const bounds = RouteMapBounds(
      south: 61.70,
      west: 34.20,
      north: 61.80,
      east: 34.40,
    );
    final padded = padRouteBoundsForPanel(bounds);

    expect(padded.south, lessThan(bounds.south));
    expect(padded.north, greaterThan(bounds.north));
    expect(padded.west, lessThan(bounds.west));
    expect(padded.east, greaterThan(bounds.east));
  });

  test('focus rect excludes top controls, safe area, and bottom panel', () {
    final rect = routeFocusRect(
      viewport: const Size(320, 640),
      safePadding: const EdgeInsets.only(top: 24, bottom: 16),
      bottomPanelHeight: 280,
    );

    expect(rect.topLeft.y, greaterThan(24));
    expect(rect.bottomRight.y, lessThan(640 - 16 - 280));
    expect(rect.bottomRight.x, lessThan(320));
  });

  test('scales native focus rect to physical map pixels', () {
    final rect = routeFocusRect(
      viewport: const Size(360, 800),
      safePadding: const EdgeInsets.only(top: 24, bottom: 16),
      bottomPanelHeight: 300,
      devicePixelRatio: 3,
    );

    expect(rect.topLeft.x, 96);
    expect(rect.topLeft.y, 408);
    expect(rect.bottomRight.x, 984);
    expect(rect.bottomRight.y, 1356);
  });

  test('centers camera targets inside the currently visible map area', () {
    final rect = visibleMapFocusRect(
      viewport: const Size(360, 700),
      margins: const EdgeInsets.fromLTRB(24, 88, 24, 320),
      devicePixelRatio: 2,
    );

    expect(rect.topLeft.x, 48);
    expect(rect.topLeft.y, 176);
    expect(rect.bottomRight.x, 672);
    expect(rect.bottomRight.y, 760);
  });

  test('selected parking bounds preserve enough local map context', () {
    const tiny = RouteMapBounds(
      south: 61.70000,
      west: 34.20000,
      north: 61.70010,
      east: 34.20010,
    );
    final contextual = ensureLocalContextBounds(tiny);

    expect(contextual.north - contextual.south, closeTo(0.0012, 1e-10));
    expect(contextual.east - contextual.west, closeTo(0.002, 1e-10));
    expect((contextual.north + contextual.south) / 2, closeTo(61.70005, 1e-8));
    expect((contextual.east + contextual.west) / 2, closeTo(34.20005, 1e-8));
  });

  test('selected parking bounds keep landmarks around larger geometry', () {
    const bounds = RouteMapBounds(
      south: 61.700,
      west: 34.200,
      north: 61.704,
      east: 34.206,
    );
    final contextual = ensureLocalContextBounds(bounds);

    expect(contextual.north - contextual.south, closeTo(0.0054, 1e-10));
    expect(contextual.east - contextual.west, closeTo(0.0081, 1e-10));
  });

  test('rejects an incomplete or invalid route', () {
    expect(calculateRouteBounds(const []), isNull);
    expect(
      calculateRouteBounds(const [Point(latitude: 61, longitude: 34)]),
      isNull,
    );
  });
}
