import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/pwa_install_eligibility.dart';

void main() {
  bool eligible({
    String userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)',
    String platform = 'iPhone',
    int maxTouchPoints = 5,
    bool navigatorStandalone = false,
    bool displayModeStandalone = false,
    String? dismissedVersion,
    bool isWeb = true,
  }) => shouldShowPwaInstallGuide(
    isWeb: isWeb,
    userAgent: userAgent,
    platform: platform,
    maxTouchPoints: maxTouchPoints,
    navigatorStandalone: navigatorStandalone,
    displayModeStandalone: displayModeStandalone,
    dismissedVersion: dismissedVersion,
  );

  test('shows in iPhone and desktop-mode iPad browsers', () {
    expect(eligible(), isTrue);
    expect(
      eligible(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X)',
        platform: 'MacIntel',
        maxTouchPoints: 5,
      ),
      isTrue,
    );
  });

  test('never shows for installed standalone PWA', () {
    expect(eligible(navigatorStandalone: true), isFalse);
    expect(eligible(displayModeStandalone: true), isFalse);
  });

  test('does not show on Android, native, or after dismissal', () {
    expect(
      eligible(
        userAgent: 'Mozilla/5.0 (Linux; Android 15)',
        platform: 'Linux armv8l',
      ),
      isFalse,
    );
    expect(eligible(isWeb: false), isFalse);
    expect(eligible(dismissedVersion: pwaInstallGuideVersion), isFalse);
  });

  test('a future guide version can be shown again', () {
    expect(eligible(dismissedVersion: '0'), isTrue);
  });
}
