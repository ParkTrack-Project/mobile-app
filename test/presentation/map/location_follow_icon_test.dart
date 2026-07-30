import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('follow icon uses a small upward navigation arrow with a top gap', () {
    final source = File(
      'lib/presentation/screens/map/widgets/location_follow_icon.dart',
    ).readAsStringSync();

    expect(source, contains('const Color(0xFF1967D2)'));
    expect(source, contains('Icons.navigation_rounded'));
    expect(source, contains('size * 0.76'));
    expect(source, contains('top: size * 0.03'));
    expect(source, contains('height: size * 0.16'));
    expect(source, contains('top: size * 0.38'));
    expect(source, isNot(contains('canvas.drawLine(')));
  });
}
