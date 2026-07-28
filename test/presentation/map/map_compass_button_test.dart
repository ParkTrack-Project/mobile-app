import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/map_compass_button.dart';

void main() {
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
}
