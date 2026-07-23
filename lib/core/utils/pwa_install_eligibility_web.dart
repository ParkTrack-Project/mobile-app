import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

bool isIosPwaEligible() {
  try {
    final navigator = web.window.navigator;
    final userAgent = navigator.userAgent.toLowerCase();
    final isIos =
        userAgent.contains('iphone') ||
        userAgent.contains('ipad') ||
        userAgent.contains('ipod') ||
        (userAgent.contains('macintosh') && navigator.maxTouchPoints > 0);
    if (!isIos) return false;

    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return false;
    }

    const version = '1';
    return web.window.localStorage.getItem('pwa_install_dismissed_v$version') ==
        null;
  } catch (error) {
    debugPrint('PWA eligibility check failed: $error');
    return false;
  }
}

void dismissIosPwaGuide() {
  const version = '1';
  web.window.localStorage.setItem('pwa_install_dismissed_v$version', 'true');
}
