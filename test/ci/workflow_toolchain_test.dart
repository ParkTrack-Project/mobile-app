import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all Flutter workflows use the tested SDK version', () {
    const expectedFlutterVersion = '3.41.7';
    final workflowDirectory = Directory('.github/workflows');
    final workflowFiles = workflowDirectory.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
    );

    final flutterWorkflows = <File>[];
    for (final workflowFile in workflowFiles) {
      final workflow = workflowFile.readAsStringSync();
      if (!workflow.contains('subosito/flutter-action@')) {
        continue;
      }

      flutterWorkflows.add(workflowFile);
      final version = RegExp(
        r'''flutter-version:\s*['"]?([^'"\s#]+)''',
      ).firstMatch(workflow)?.group(1);

      expect(
        version,
        expectedFlutterVersion,
        reason:
            '${workflowFile.path} must pin the Flutter version so a new '
            'stable Dart SDK cannot break the locked code-generation tools.',
      );
    }

    expect(
      flutterWorkflows,
      isNotEmpty,
      reason: 'At least one Flutter GitHub Actions workflow must be checked.',
    );
  });
}
