import 'dart:async';
import 'dart:convert';

import 'package:airlink_manager/controller.dart';
import 'package:airlink_manager/main.dart';
import 'package:airlink_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Json telemetry() {
  final j = demoSnapshot(true, 0, DateTime.now().toUtc()).json;
  j.addAll({
    'mode': 'live',
    'device_id': 'test',
    'controls': {
      'poe_ports': ['ether1'],
    },
  });
  j['device']['verified'] = true;
  return j;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('malformed control capabilities are rejected before rendering', () {
    for (final controls in [
      true,
      {'poe_ports': 'ether1'},
      {
        'poe_ports': [12],
      },
    ]) {
      final j = telemetry()..['controls'] = controls;
      expect(() => Snapshot.live(j, 'test'), throwsFormatException);
    }
  });

  test('control uses a separate token, blocks polling, and never retries lost writes', () async {
    var reads = 0, writes = 0;
    final requests = <http.Request>[];
    final c = AirlinkController(
      client: MockClient((r) async {
        requests.add(r);
        if (r.method == 'GET') {
          reads++;
          expect(r.headers['Authorization'], 'Bearer monitor-token');
          return http.Response(jsonEncode(telemetry()), 200);
        }
        expect(r.headers['Authorization'], 'Bearer operator-token');
        expect(r.followRedirects, false);
        if (r.url.path.endsWith('/prepare')) {
          expect(jsonDecode(r.body)['mode'], 'off');
          return http.Response(
            jsonEncode({
              'confirmation_id': 'n' * 43,
              'device_id': 'test',
              'port': 'ether1',
              'name': 'ether1',
              'requested_mode': 'off',
              'previous_mode': 'auto-on',
            }),
            200,
          );
        }
        writes++;
        expect(jsonDecode(r.body)['confirmed'], true);
        throw TimeoutException('reply lost');
      }),
    )..setInterval(0);
    await c.connect(
      const Profile('Test', 'https://backend.example', 'test'),
      'monitor-token',
    );
    final port = c.snapshot!.ports.first;
    expect(c.canControlPoe(c.snapshot!.ports[1]), false);
    expect(c.canControlPoe(c.snapshot!.ports.last), false);
    final epoch = c.beginPoe(port);
    final prepared = await c.preparePoe(port, 'off', 'operator-token', epoch);
    await c.refresh();
    expect(reads, 1);
    await expectLater(
      c.commitPoe(prepared, 'operator-token', epoch),
      throwsStateError,
    );
    expect(c.snapshot!.stale, true);
    expect(writes, 1);
    await c.endPoe(epoch);
    expect(reads, 2);
    expect(writes, 1);
    c.dispose();
  });

  test('disconnect invalidates prepared control before a write', () async {
    var posts = 0;
    final c = AirlinkController(
      client: MockClient((r) async {
        if (r.method == 'POST') posts++;
        return http.Response(jsonEncode(telemetry()), 200);
      }),
    )..setInterval(0);
    await c.connect(
      const Profile('Test', 'https://backend.example', 'test'),
      'monitor',
    );
    final epoch = c.beginPoe(c.snapshot!.ports.first);
    c.disconnect();
    await expectLater(
      c.commitPoe({'confirmation_id': 'old'}, 'operator', epoch),
      throwsStateError,
    );
    expect(posts, 0);
    c.dispose();
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'PoE requires explicit approval and demo never sends commands at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var networkCalls = 0;
        final c = AirlinkController(
          client: MockClient((_) async {
            networkCalls++;
            return http.Response('{}', 500);
          }),
        )..setInterval(0);
        await tester.pumpWidget(AirlinkApp(controller: c));
        await tester.pumpAndSettle();
        c.startDemo(true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('PoE').last);
        await tester.pumpAndSettle();
        final off = find.byKey(const Key('poe-off-ether1'));
        await tester.ensureVisible(off);
        await tester.tap(off);
        await tester.pumpAndSettle();
        expect(find.textContaining('management connection'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(c.snapshot!.ports.first['poe']['configuration_mode'], 'auto-on');
        await tester.ensureVisible(off);
        await tester.tap(off);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review current setting'));
        await tester.pumpAndSettle();
        final confirm = find.byKey(const Key('poe-confirm'));
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.ensureVisible(
          find.byKey(const Key('poe-acknowledgement')),
        );
        await tester.tap(find.byKey(const Key('poe-acknowledgement')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(c.snapshot!.ports.first['poe']['configuration_mode'], 'off');
        expect(c.snapshot!.ports.first['poe']['power_w'], 0);
        await c.refresh();
        expect(c.snapshot!.ports.first['poe']['configuration_mode'], 'off');
        expect(networkCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
