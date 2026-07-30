import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/map_compass_button.dart';

void main() {
  double compassAngle(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.byKey(const Key('map_compass_rotation')),
    );
    final matrix = transform.transform.storage;
    return math.atan2(matrix[1], matrix[0]);
  }

  test('uses a dark map-control surface and a lighter divider', () {
    final surface = mapControlSurfaceColorFor(Brightness.dark);
    final divider = mapControlDividerColorFor(Brightness.dark);

    expect(surface.computeLuminance(), lessThan(0.1));
    expect(
      divider.computeLuminance(),
      greaterThan(surface.withValues(alpha: 1).computeLuminance()),
    );
    expect(
      mapControlSurfaceColorFor(Brightness.light),
      isNot(mapControlSurfaceColorFor(Brightness.dark)),
    );
  });

  testWidgets('uses the reduced compass artwork inside a 52 dp button', (
    tester,
  ) async {
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapCompassButton(
              azimuth: 30,
              onPressed: () => pressed = true,
              tooltip: 'Compass',
            ),
          ),
        ),
      ),
    );

    final icon = tester.widget<CustomPaint>(
      find.byKey(const Key('map_compass_icon')),
    );
    expect(icon.size, const Size(18, 24));
    expect(tester.getSize(find.byType(MapCompassButton)), const Size(52, 52));

    await tester.tap(find.byType(MapCompassButton));
    expect(pressed, isTrue);
  });

  testWidgets('uses the dark control surface in dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MapCompassButton(
            azimuth: 0,
            onPressed: () {},
            tooltip: 'Compass',
          ),
        ),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find.byKey(const Key('map_compass_button_surface')),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, mapControlSurfaceColorFor(Brightness.dark));
  });

  testWidgets('tracks azimuth immediately without tweening through north', (
    tester,
  ) async {
    final azimuth = ValueNotifier<double>(359);
    addTearDown(azimuth.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: azimuth,
            builder: (context, value, _) => MapCompassButton(
              azimuth: value,
              onPressed: () {},
              tooltip: 'Compass',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(compassAngle(tester), closeTo(math.pi / 180, 0.0001));

    azimuth.value = 0;
    await tester.pump();

    expect(compassAngle(tester), closeTo(0, 0.0001));
  });
}
