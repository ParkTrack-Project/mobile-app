import 'package:share_plus/share_plus.dart' show ShareParams;

Uri buildShareMailtoUri(ShareParams params) {
  final text = params.text ?? params.uri?.toString();
  if (text == null || text.isEmpty) {
    throw ArgumentError('Share text cannot be empty');
  }

  final queryParameters = <String, String>{'body': text};
  final subject = params.subject;
  if (subject != null && subject.isNotEmpty) {
    queryParameters['subject'] = subject;
  }
  return Uri(scheme: 'mailto', queryParameters: queryParameters);
}
