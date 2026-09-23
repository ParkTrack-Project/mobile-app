import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Google Play workflow fills only an empty GitHub release description',
    () {
      final workflow = File(
        '.github/workflows/publish-google-play.yml',
      ).readAsStringSync();

      expect(
        workflow,
        contains('name: Populate empty GitHub release description'),
      );
      expect(
        workflow,
        contains(
          r"""gh release view "$RELEASE_TAG" --json body --jq '.body'""",
        ),
      );
      expect(workflow, contains(r'[[ "$RELEASE_BODY" =~ [^[:space:]] ]]'));
      expect(
        workflow,
        contains(
          r'NOTES_PATH="distribution/releases/$VERSION/github-release-notes.md"',
        ),
      );
      expect(workflow, contains(r'test -s "$NOTES_PATH"'));
      expect(
        workflow,
        contains(r'gh release edit "$RELEASE_TAG" --notes-file "$NOTES_PATH"'),
      );
    },
  );
}
