import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/map_bottom_panel_switcher.dart';

void main() {
  testWidgets('slides a panel through its full height on entry and exit', (
    tester,
  ) async {
    Widget app(Widget? child) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 300,
            child: MapBottomPanelSwitcher(
              transitionKey: 'parking',
              child: child,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(null));
    await tester.pumpWidget(
      app(
        const SizedBox(key: ValueKey('parking_panel'), height: 180, width: 300),
      ),
    );

    SlideTransition transition() => tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('parking_panel')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );

    expect(transition().position.value.dy, 1);
    await tester.pump(const Duration(milliseconds: 160));
    expect(transition().position.value.dy, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(transition().position.value, Offset.zero);

    await tester.pumpWidget(app(null));
    await tester.pump(const Duration(milliseconds: 120));
    expect(transition().position.value.dy, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parking_panel')), findsNothing);
  });
}
