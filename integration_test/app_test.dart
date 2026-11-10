import 'dart:convert';
import 'dart:ui' as ui;

import 'package:airlink_manager/controller.dart';
import 'package:airlink_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native application walkthrough and actual rendered screenshots',
    (tester) async {
      await binding.setSurfaceSize(const Size(1440, 1180));
      final controller = AirlinkController()..setInterval(0);
      final capture = GlobalKey();
      final screenshots = <String, String>{};
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: AirlinkApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> screenshot(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        screenshots[name] = base64Encode(bytes!.buffer.asUint8List());
        image.dispose();
      }

      expect(find.text('Connect to your backend'), findsOneWidget);
      await screenshot('connection-macos');
      await tester.ensureVisible(find.text('Demo · netPower 16P'));
      await tester.tap(find.text('Demo · netPower 16P'));
      await tester.pumpAndSettle();
      expect(find.textContaining('DEMO MODE'), findsOneWidget);
      await screenshot('demo-netpower-overview-macos');
      for (final section in ['Ports', 'Traffic', 'PoE', 'System']) {
        await tester.tap(find.text(section).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (section == 'Traffic') await screenshot('demo-traffic-macos');
        if (section == 'PoE') {
          await screenshot('demo-poe-controls-macos');
          await tester.ensureVisible(find.byKey(const Key('poe-off-ether1')));
          await tester.tap(find.byKey(const Key('poe-off-ether1')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Review current setting'));
          await tester.pumpAndSettle();
          await screenshot('demo-poe-confirmation-macos');
          await tester.tap(find.byKey(const Key('poe-acknowledgement')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('poe-confirm')));
          await tester.pumpAndSettle();
          expect(
            controller.snapshot!.ports.first['poe']['configuration_mode'],
            'off',
          );
        }
      }
      await screenshot('demo-system-macos');
      await tester.tap(find.byTooltip('Disconnect'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Demo · CRS112'));
      await tester.tap(find.text('Demo · CRS112'));
      await tester.pumpAndSettle();
      expect(controller.snapshot!.ports.length, 12);
      await screenshot('demo-crs112-overview-macos');
      await binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await screenshot('demo-mobile-layout-macos');
      await binding.setSurfaceSize(null);
      binding.reportData = {
        'rendered_screenshots': screenshots,
        'platform': 'macOS native Flutter',
        'mode': 'explicit demo, simulated telemetry',
      };
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
