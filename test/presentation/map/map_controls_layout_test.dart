import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/map_screen.dart';

void main() {
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
}
