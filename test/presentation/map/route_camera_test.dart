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

  test('selected parking bounds preserve enough local map context', () {
    const tiny = RouteMapBounds(
      south: 61.70000,
      west: 34.20000,
      north: 61.70010,
      east: 34.20010,
    );
    final contextual = ensureLocalContextBounds(tiny);

    expect(contextual.north - contextual.south, closeTo(0.0025, 1e-10));
    expect(contextual.east - contextual.west, closeTo(0.004, 1e-10));
    expect((contextual.north + contextual.south) / 2, closeTo(61.70005, 1e-8));
    expect((contextual.east + contextual.west) / 2, closeTo(34.20005, 1e-8));
  });

  test('rejects an incomplete or invalid route', () {
    expect(calculateRouteBounds(const []), isNull);
    expect(
      calculateRouteBounds(const [Point(latitude: 61, longitude: 34)]),
      isNull,
    );
  });
}
