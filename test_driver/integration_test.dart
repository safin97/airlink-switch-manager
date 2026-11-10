import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      final screenshots =
          data?['rendered_screenshots'] as Map<String, dynamic>?;
      if (screenshots == null || screenshots.isEmpty) {
        throw StateError('No native screenshots received');
      }
      await Directory('docs/screenshots').create(recursive: true);
      for (final entry in screenshots.entries) {
        await File('docs/screenshots/${entry.key}.png')
            .writeAsBytes(base64Decode(entry.value as String));
      }
      await File('docs/screenshots/capture.json').writeAsString(
        jsonEncode({
          'platform': data!['platform'],
          'mode': data['mode'],
          'method': 'RenderRepaintBoundary.toImage in integration_test running on native macOS; exported through Flutter driver',
          'screenshots': screenshots.keys.toList(),
        }),
      );
    },
  );
}
