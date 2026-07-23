export 'pwa_install_eligibility_stub.dart'
    if (dart.library.js_interop) 'pwa_install_eligibility_web.dart';

const pwaInstallGuideVersion = '1';

bool shouldShowPwaInstallGuide({
  required bool isWeb,
  required String userAgent,
  required String platform,
  required int maxTouchPoints,
  required bool navigatorStandalone,
  required bool displayModeStandalone,
  required String? dismissedVersion,
}) {
  if (!isWeb || navigatorStandalone || displayModeStandalone) return false;

  final normalizedAgent = userAgent.toLowerCase();
  final normalizedPlatform = platform.toLowerCase();
  final isIphoneOrIpad =
      normalizedAgent.contains('iphone') ||
      normalizedAgent.contains('ipad') ||
      normalizedAgent.contains('ipod') ||
      (normalizedPlatform == 'macintel' && maxTouchPoints > 1);
  if (!isIphoneOrIpad) return false;

  return dismissedVersion != pwaInstallGuideVersion;
}
