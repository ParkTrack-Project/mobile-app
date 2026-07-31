import 'package:share_plus/share_plus.dart';

Future<void> shareParkTrackParams(ShareParams params) async {
  await SharePlus.instance.share(params);
}
