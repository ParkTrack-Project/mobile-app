import 'package:flutter/foundation.dart';
import 'dart:js_interop' as js;
import 'package:web/web.dart' as web;

bool isIosPwaEligible() {
  if (!kIsWeb) return false;

  final userAgent = web.window.navigator.userAgent.toLowerCase();
  final isIos = userAgent.contains('iphone') || 
                userAgent.contains('ipad') || 
                userAgent.contains('ipod');
  
  if (!isIos) return false;

  // Check if already in standalone mode
  final isStandalone = web.window.matchMedia('(display-mode: standalone)').matches ||
                       (web.window.navigator as dynamic).standalone == true;

  if (isStandalone) return false;

  // Check if dismissed for this version
  const version = '1';
  final dismissed = web.window.localStorage.getItem('pwa_install_dismissed_v$version');
  
  return dismissed == null;
}

void dismissIosPwaGuide() {
  if (!kIsWeb) return;
  const version = '1';
  web.window.localStorage.setItem('pwa_install_dismissed_v$version', 'true');
}
