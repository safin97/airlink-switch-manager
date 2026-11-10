import 'dart:convert';

import 'package:airlink_manager/firmware_manifest.dart';
import 'package:airlink_manager/firmware_updates.dart';
import 'package:airlink_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Json descriptor() => {
  'schema': 'airlink.firmware-manifest.draft1',
  'product': 'CRS112-8P-4S-IN',
  'architecture': 'mipsbe',
  'board_revision': 'r2',
  'version': '0.0.0-test',
  'image_type': 'sysupgrade',
  'sha256': List.filled(64, 'a').join(),
  'size_bytes': 1024,
};

void main() {
  test(
    'descriptor rejects malformed, oversized and misleading declarations',
    () {
      for (final text in [
        '[]',
        '{}',
        '{',
        List.filled(16385, ' ').join(),
        jsonEncode({...descriptor(), 'architecture': 'arm'}),
        jsonEncode({...descriptor(), 'product': 'CRS109'}),
        jsonEncode({...descriptor(), 'board_revision': '*'}),
        jsonEncode({...descriptor(), 'sha256': 'bad'}),
        jsonEncode({...descriptor(), 'size_bytes': -1}),
        jsonEncode({...descriptor(), 'size_bytes': 1.5}),
        jsonEncode({...descriptor(), 'image_type': 'kernel'}),
        jsonEncode({...descriptor(), 'signature_verified': true}),
      ]) {
        expect(() => FirmwareManifest.parse(text), throwsFormatException);
      }
    },
  );

  test('matching declarations require a fresh verified identity and exact revision', () {
    final m = FirmwareManifest.parse(jsonEncode(descriptor()));
    final s = demoSnapshot(true, 0, DateTime.now());
    expect(m.compatibilityIssues(s, demo: true, stale: true).length, 4);
    s.device['verified'] = true;
    s.device['board_revision'] = 'r2';
    expect(m.compatibilityIssues(s, demo: false, stale: false), isEmpty);
    s.device['board_revision'] = 'r4';
    expect(
      m.compatibilityIssues(s, demo: false, stale: false).single,
      contains('board_revision mismatch'),
    );
    final other = demoSnapshot(false, 0, DateTime.now());
    expect(
      m
          .compatibilityIssues(other, demo: false, stale: false)
          .where((e) => e.contains('mismatch'))
          .length,
      2,
    );
  });

  testWidgets(
    'review never enables installation, edits clear results and stale identity is rechecked',
    (tester) async {
      final s = demoSnapshot(true, 0, DateTime.now());
      s.device['verified'] = true;
      s.device['board_revision'] = 'r2';
      Widget screen(bool stale) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FirmwareUpdates(snapshot: s, demo: false, stale: stale),
          ),
        ),
      );
      await tester.pumpWidget(screen(false));
      final field = find.byKey(const Key('firmware-manifest'));
      await tester.enterText(field, jsonEncode(descriptor()));
      await tester.ensureVisible(find.byKey(const Key('firmware-review')));
      await tester.tap(find.byKey(const Key('firmware-review')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Declared target matches'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('firmware-install')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(screen(true));
      expect(find.textContaining('Device readings are stale.'), findsOneWidget);
      await tester.enterText(field, '{}');
      await tester.pump();
      expect(find.textContaining('Declared version:'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('firmware-review')));
      await tester.tap(find.byKey(const Key('firmware-review')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Expected exactly:'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('firmware-install')))
            .onPressed,
        isNull,
      );
    },
  );
}
