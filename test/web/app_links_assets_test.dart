import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PWA manifest is scoped for path-based app links', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest['id'], '/');
    expect(manifest['start_url'], '/map');
    expect(manifest['scope'], '/');
    expect(
      (manifest['launch_handler'] as Map<String, dynamic>)['client_mode'],
      'navigate-existing',
    );
  });

  test('Android intent filter handles only the ParkTrack mobile host', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:autoVerify="true"'));
    expect(manifest, contains('android:scheme="https"'));
    expect(manifest, contains('android:host="m.parktrack.live"'));
    expect(manifest, isNot(contains('android:host="*.parktrack.live"')));
  });

  test('asset links placeholder stays valid and never uses a debug key', () {
    final assetLinks = jsonDecode(
      File('web/.well-known/assetlinks.json').readAsStringSync(),
    );

    expect(assetLinks, isA<List<dynamic>>());
    expect(assetLinks, isEmpty);
  });

  test('web deployment provides a direct-path fallback', () {
    final workflow = File(
      '.github/workflows/deploy-web.yml',
    ).readAsStringSync();

    expect(workflow, contains('cp build/web/index.html build/web/404.html'));
  });
}
