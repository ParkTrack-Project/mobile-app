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
    expect(manifest, contains('android:scheme="parktrack"'));
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
        '52:9C:D3:24:95:AD:28:AB:08:F6:AE:C5:09:19:87:43:E4:9D:E8:0D:39:55:1B:A2:60:00:C6:AB:B9:B9:6D:BE',
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
