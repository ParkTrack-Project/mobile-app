import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label {
    final buildSuffix = buildNumber.isEmpty ? '' : '+$buildNumber';
    return 'ParkTrack v$version$buildSuffix';
  }
}

final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return AppVersion(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
  );
});
