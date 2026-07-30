import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/android_heading_source.dart';

void main() {
  test('normalizes an initial heading', () {
    expect(smoothCircularHeading(-10, null), 350);
    expect(smoothCircularHeading(370, null), 10);
  });

  test('smooths across north using the shortest circular path', () {
    expect(smoothCircularHeading(10, 350, alpha: 0.5), closeTo(0, 0.0001));
    expect(smoothCircularHeading(350, 10, alpha: 0.5), closeTo(0, 0.0001));
  });
}
