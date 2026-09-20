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

  test('local web root contains the production Android app identity', () {
    final assetLinks =
        jsonDecode(File('web/.well-known/assetlinks.json').readAsStringSync())
            as List<dynamic>;

    expect(assetLinks, hasLength(1));
    final entry = assetLinks.single as Map<String, dynamic>;
    expect(
      entry['relation'],
      contains('delegate_permission/common.handle_all_urls'),
    );
    expect(
      entry['relation'],
      contains('delegate_permission/common.get_login_creds'),
    );

    final target = entry['target'] as Map<String, dynamic>;
    expect(target['namespace'], 'android_app');
    expect(target['package_name'], 'com.parktrack.mobile');
    expect(
      target['sha256_cert_fingerprints'],
      containsAll([
        '52:9C:D3:24:95:AD:28:AB:08:F6:AE:C5:09:19:87:43:E4:9D:E8:0D:39:55:1B:A2:60:00:C6:AB:B9:B9:6D:BE',
        'B8:0A:91:ED:3C:71:8F:0B:21:53:82:9D:85:41:AA:93:CB:A0:54:1F:AF:E2:ED:4E:F4:61:4A:F9:75:A6:ED:D0',
      ]),
    );
  });

  test('web deployment uploads a Pages tar that retains hidden files', () {
    final workflow = File(
      '.github/workflows/deploy-web.yml',
    ).readAsStringSync();

    expect(workflow, contains('cp build/web/index.html build/web/404.html'));
    expect(
      workflow,
      contains(
        'bash tool/prepare_pages_artifact.sh\n'
        '          build/web\n'
        '          "\$RUNNER_TEMP/artifact.tar"',
      ),
    );
    expect(workflow, contains('name: github-pages'));
    expect(workflow, contains(r'path: ${{ runner.temp }}/artifact.tar'));
    expect(workflow, isNot(contains('actions/upload-pages-artifact')));
    expect(workflow, isNot(contains('include-hidden-files')));
  });

  test(
    'Pages artifact preparation keeps the Digital Asset Links document',
    () async {
      final temporaryDirectory = Directory.systemTemp.createTempSync(
        'parktrack-pages-artifact-',
      );
      addTearDown(() => temporaryDirectory.deleteSync(recursive: true));

      final webRoot = Directory('${temporaryDirectory.path}/web')
        ..createSync(recursive: true);
      File('${webRoot.path}/index.html').writeAsStringSync('index');
      File('${webRoot.path}/404.html').writeAsStringSync('fallback');
      File('${webRoot.path}/.well-known/assetlinks.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('[]');
      final artifactPath = '${temporaryDirectory.path}/artifact.tar';

      final preparation = await Process.run('bash', [
        'tool/prepare_pages_artifact.sh',
        webRoot.path,
        artifactPath,
      ]);
      expect(
        preparation.exitCode,
        0,
        reason: '${preparation.stdout}\n${preparation.stderr}',
      );

      final listing = await Process.run('tar', ['-tf', artifactPath]);
      expect(
        listing.exitCode,
        0,
        reason: '${listing.stdout}\n${listing.stderr}',
      );
      expect(
        (listing.stdout as String).split('\n'),
        contains('./.well-known/assetlinks.json'),
      );
    },
    skip: Platform.isWindows,
  );

  test('release documentation lists every supported HTTPS section', () {
    final documentation = File('docs/deep-links.md').readAsStringSync();

    for (final path in const [
      '/map',
      '/parking/42',
      '/route/7',
      '/destination?lat=',
      '/search?q=',
      '/profile',
      '/profile/edit',
      '/login',
      '/register',
      '/password-reset',
    ]) {
      expect(documentation, contains('https://m.parktrack.live$path'));
    }
  });
}
