import 'package:web/web.dart' as web;

String? detectBrowserLanguage() {
  final language = web.window.navigator.language.trim().toLowerCase();
  return language.isEmpty ? null : language;
}
