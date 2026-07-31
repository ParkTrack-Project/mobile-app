import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/location_follow_icon.dart';

void main() {
  testWidgets('follow icon keeps the arrow visible with line on both sides', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: LocationFollowIcon(size: 100))),
    );

    final iconRect = tester.getRect(find.byType(LocationFollowIcon));
    final arrowRect = tester.getRect(
      find.byKey(const Key('location_follow_arrow')),
    );
    final topLineRect = tester.getRect(
      find.byKey(const Key('location_follow_top_line')),
    );
    final bottomLineRect = tester.getRect(
      find.byKey(const Key('location_follow_bottom_line')),
    );
    final arrow = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('location_follow_arrow')),
        matching: find.byType(Icon),
      ),
    );

    expect(arrow.icon, Icons.navigation_rounded);
    expect(arrow.size, 68);
    expect(arrowRect.top, greaterThanOrEqualTo(iconRect.top));
    expect(arrowRect.bottom, lessThanOrEqualTo(iconRect.bottom));
    expect(topLineRect.top, lessThan(arrowRect.top));
    expect(topLineRect.bottom, greaterThan(arrowRect.top));
    expect(bottomLineRect.top, lessThan(arrowRect.bottom));
    expect(bottomLineRect.bottom, lessThanOrEqualTo(iconRect.bottom));
  });
}
