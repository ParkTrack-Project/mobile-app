import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/widgets/destination_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('destination marker is a bottom-anchored high-resolution pin', () async {
    final bytes = await buildDestinationPinBitmap();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    expect(destinationMarkerAnchor.dx, 0.5);
    expect(destinationMarkerAnchor.dy, 1);
    expect(frame.image.width, destinationMarkerSize.width);
    expect(frame.image.height, destinationMarkerSize.height);
  });
}
