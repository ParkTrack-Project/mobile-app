import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/map_screen.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  test('queued zoom taps accumulate and clamp without losing input', () {
    final first = nextQueuedMapZoom(
      currentZoom: 14,
      queuedZoom: null,
      delta: 1,
    );
    final second = nextQueuedMapZoom(
      currentZoom: 14,
      queuedZoom: first,
      delta: 1,
    );
    final clamped = nextQueuedMapZoom(
      currentZoom: 20,
      queuedZoom: second,
      delta: 10,
    );

    expect(first, 15);
    expect(second, 16);
    expect(clamped, 21);
  });

  test('recognizes north across the zero-degree boundary', () {
    expect(isMapNorthUp(0), isTrue);
    expect(isMapNorthUp(0.5), isTrue);
    expect(isMapNorthUp(359.5), isTrue);
    expect(isMapNorthUp(358), isFalse);
    expect(isMapNorthUp(-0.5), isTrue);
    expect(isMapNorthUp(double.nan), isFalse);
  });

  test('centers zoom controls when lower controls do not interfere', () {
    expect(
      resolveZoomControlsBottom(viewportHeight: 800, mapControlsBottom: 12),
      347.5,
    );
  });

  test('moves zoom controls above controls anchored below them', () {
    expect(
      resolveZoomControlsBottom(viewportHeight: 800, mapControlsBottom: 420),
      482,
    );
  });

  test('keeps all map controls visible above a route preview card', () {
    final mapControlsBottom = resolveMapControlsBottom(
      mapPanelHeight: 190,
      parkingFabVisible: false,
      panelVisible: true,
    );

    expect(mapControlsBottom, 202);
    expect(
      shouldShowZoomControls(
        viewportHeight: 717,
        mapControlsBottom: mapControlsBottom,
      ),
      isTrue,
    );
    expect(
      shouldShowLowerMapControls(
        viewportHeight: 717,
        mapControlsBottom: mapControlsBottom,
      ),
      isTrue,
    );
    expect(
      resolveZoomControlsBottom(
        viewportHeight: 717,
        mapControlsBottom: mapControlsBottom,
      ),
      306,
    );
  });

  test('keeps lower controls above the destination card with a gap', () {
    expect(
      resolveMapControlsBottom(
        mapPanelHeight: 168,
        mapPanelBottom: 12,
        parkingFabVisible: false,
        panelVisible: true,
      ),
      192,
    );
    expect(
      resolveMapControlsBottom(
        mapPanelHeight: 168,
        parkingFabVisible: false,
        panelVisible: true,
      ),
      180,
    );
  });

  test('hides lower controls before they reach the top controls', () {
    expect(
      shouldShowLowerMapControls(viewportHeight: 800, mapControlsBottom: 635),
      isTrue,
    );
    expect(
      shouldShowLowerMapControls(viewportHeight: 800, mapControlsBottom: 637),
      isFalse,
    );
    expect(
      shouldShowLowerMapControls(
        viewportHeight: 800,
        mapControlsBottom: 700,
        forceVisible: true,
      ),
      isTrue,
    );
  });

  test('suppresses a background tap immediately following a parking tap', () {
    final now = DateTime(2026, 7, 28, 12);

    expect(
      shouldIgnoreMapBackgroundTap(
        lastZoneTapAt: now.subtract(const Duration(milliseconds: 100)),
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldIgnoreMapBackgroundTap(
        lastZoneTapAt: now.subtract(const Duration(milliseconds: 250)),
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldIgnoreMapBackgroundTap(lastZoneTapAt: null, now: now),
      isFalse,
    );
  });

  test('interpolates map points through the shortest longitude path', () {
    final point = interpolateMapPoint(
      const Point(latitude: 10, longitude: 179),
      const Point(latitude: 12, longitude: -179),
      0.5,
    );

    expect(point.latitude, 11);
    expect(point.longitude.abs(), 180);
    expect(shortestLongitudeDelta(179, -179), 2);
  });
}
