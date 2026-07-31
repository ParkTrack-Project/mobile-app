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
    const route = [
      Point(latitude: 61.78, longitude: 34.34),
      Point(latitude: 61.80, longitude: 34.42),
      Point(latitude: 61.82, longitude: 34.36),
    ];
    const viewport = Size(360, 800);
    const margins = EdgeInsets.fromLTRB(32, 112, 32, 292);
    final plan = calculateRouteCameraPlan(
      route,
      viewport: viewport,
      margins: margins,
    );

    expect(plan, isNotNull);
    expect(plan!.zoom, inInclusiveRange(3, 21));
    expect(plan.azimuth, inInclusiveRange(0, 360));
    for (final point in route) {
      final screenPoint = projectRoutePointToViewport(
        point,
        plan,
        viewport: viewport,
      );
      expect(screenPoint.dx, inInclusiveRange(margins.left, 328));
      expect(screenPoint.dy, inInclusiveRange(margins.top, 508));
    }
  });

  test('places the route finish above the route start in preview', () {
    const route = [
      Point(latitude: 61.78, longitude: 34.34),
      Point(latitude: 61.79, longitude: 34.38),
      Point(latitude: 61.82, longitude: 34.36),
    ];
    const viewport = Size(360, 800);
    final plan = calculateRouteCameraPlan(
      route,
      viewport: viewport,
      margins: const EdgeInsets.fromLTRB(32, 112, 32, 292),
    );

    expect(plan, isNotNull);
    final start = projectRoutePointToViewport(
      route.first,
      plan!,
      viewport: viewport,
    );
    final finish = projectRoutePointToViewport(
      route.last,
      plan,
      viewport: viewport,
    );

    expect(finish.dy, lessThan(start.dy));
  });

  test('fits the complete web route on a small margined viewport', () {
    const route = [
      Point(latitude: 55.7558, longitude: 37.6173),
      Point(latitude: 56.8587, longitude: 35.9176),
      Point(latitude: 57.6261, longitude: 39.8845),
      Point(latitude: 59.2205, longitude: 39.8915),
      Point(latitude: 61.7849, longitude: 34.3469),
    ];
    const viewport = Size(371, 715);
    const margins = EdgeInsets.fromLTRB(32, 112, 32, 271);
    final plan = calculateRouteCameraPlanWithMapMargins(
      route,
      viewport: viewport,
      margins: margins,
    );

    expect(plan, isNotNull);
    final cameraPlan = plan!;
    for (final point in route) {
      final screenPoint = projectRoutePointToViewport(
        point,
        cameraPlan,
        viewport: viewport,
        cameraMargins: margins,
      );
      expect(
        screenPoint.dx,
        inInclusiveRange(margins.left, viewport.width - margins.right),
      );
      expect(
        screenPoint.dy,
        inInclusiveRange(margins.top, viewport.height - margins.bottom),
      );
    }

    final start = projectRoutePointToViewport(
      route.first,
      cameraPlan,
      viewport: viewport,
      cameraMargins: margins,
    );
    final finish = projectRoutePointToViewport(
      route.last,
      cameraPlan,
      viewport: viewport,
      cameraMargins: margins,
    );
    expect(finish.dy, lessThan(start.dy));
  });

  test('fits a very long web route below zoom 3 on a narrow viewport', () {
    const route = [
      Point(latitude: 55.8642, longitude: -4.2518),
      Point(latitude: 55.9533, longitude: 23.4167),
      Point(latitude: 55.7558, longitude: 37.6173),
      Point(latitude: 55.0302, longitude: 60.1084),
      Point(latitude: 55.0084, longitude: 82.9357),
    ];
    const viewport = Size(381, 717);
    const margins = EdgeInsets.fromLTRB(32, 112, 32, 221);
    final plan = calculateRouteCameraPlanWithMapMargins(
      route,
      viewport: viewport,
      margins: margins,
    );

    expect(plan, isNotNull);
    expect(plan!.zoom, lessThan(3));
    for (final point in route) {
      final screenPoint = projectRoutePointToViewport(
        point,
        plan,
        viewport: viewport,
        cameraMargins: margins,
      );
      expect(screenPoint.dx - 16, greaterThanOrEqualTo(0));
      expect(screenPoint.dx + 16, lessThanOrEqualTo(viewport.width));
      expect(screenPoint.dy - 40, greaterThanOrEqualTo(0));
      expect(screenPoint.dy, lessThanOrEqualTo(viewport.height));
    }
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
