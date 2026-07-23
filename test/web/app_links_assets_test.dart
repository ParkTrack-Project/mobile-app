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

  test('asset links contains the production Android app identity', () {
    final assetLinks =
        jsonDecode(File('web/.well-known/assetlinks.json').readAsStringSync())
            as List<dynamic>;

    expect(assetLinks, hasLength(1));
    final entry = assetLinks.single as Map<String, dynamic>;
    expect(
      entry['relation'],
      contains('delegate_permission/common.handle_all_urls'),
    );

    final target = entry['target'] as Map<String, dynamic>;
    expect(target['namespace'], 'android_app');
    expect(target['package_name'], 'com.parktrack.mobile');
    expect(
      target['sha256_cert_fingerprints'],
      contains(
        'B8:0A:91:ED:3C:71:8F:0B:21:53:82:9D:85:41:AA:93:CB:A0:54:1F:AF:E2:ED:4E:F4:61:4A:F9:75:A6:ED:D0',
      ),
    );
  });

  test('web deployment provides a direct-path fallback', () {
    final workflow = File(
      '.github/workflows/deploy-web.yml',
    ).readAsStringSync();

    expect(workflow, contains('cp build/web/index.html build/web/404.html'));
  });
}
