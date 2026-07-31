import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:share_plus/share_plus.dart' show ShareParams;
import 'package:web/web.dart' as web;

import 'app_share_platform_shared.dart';

Future<void> shareParkTrackParams(ShareParams params) async {
  final navigator = web.window.navigator;
  final data = _shareData(params);

  if (!navigator.has('share') ||
      (navigator.has('canShare') && !navigator.canShare(data))) {
    _openEmailFallback(params);
    return;
  }

  try {
    await navigator.share(data).toDart;
  } on web.DOMException catch (error) {
    if (error.name == 'AbortError') return;
    _openEmailFallback(params);
  }
}

web.ShareData _shareData(ShareParams params) {
  final uri = params.uri?.toString();
  final text = params.text;
  final title = params.subject ?? params.title;

  if (uri != null) return web.ShareData(url: uri);
  if (text == null || text.isEmpty) {
    throw ArgumentError('Share text cannot be empty');
  }
  if (title != null) return web.ShareData(text: text, title: title);
  return web.ShareData(text: text);
}

void _openEmailFallback(ShareParams params) {
  if (!params.mailToFallbackEnabled) {
    throw UnsupportedError('Web Share API is unavailable');
  }
  web.window.location.href = buildShareMailtoUri(params).toString();
}
