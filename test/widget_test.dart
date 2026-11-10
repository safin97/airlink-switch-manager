import 'dart:async';
import 'dart:convert';

import 'package:airlink_manager/controller.dart' as air;
import 'package:airlink_manager/main.dart';
import 'package:airlink_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remote HTTP and credential-bearing URLs are rejected', () {
    for (final url in [
      'http://192.168.88.1',
      'https://user:pass@example.com',
      'https://host/path',
      'https://host?token=secret',
      'file:///tmp',
    ]) {
      expect(() => validateBackend(url), throwsFormatException);
    }
    expect(validateBackend('http://127.0.0.1:8000').host, '127.0.0.1');
    expect(validateBackend('https://backend.example').scheme, 'https');
    expect(reading(null, 'V'), 'Unavailable');
  });

  test('demo layouts have correct physical ports', () {
    for (final small in [false, true]) {
      final s = demoSnapshot(small, 1, DateTime.now());
      expect(s.ports.length, small ? 12 : 18);
      expect(
        s.ports.where((p) => p['kind'] == 'Ethernet').length,
        small ? 8 : 16,
      );
    }
  });

  test('incomplete nested telemetry is rejected before rendering', () {
    final j = demoSnapshot(false, 1, DateTime.now().toUtc()).json;
    j.addAll({'mode': 'live', 'device_id': 'tower'});
    j['device']['verified'] = true;
    j['ports'][0]['poe'] = null;
    expect(() => Snapshot.live(j, 'tower'), throwsFormatException);
  });

  test('profiles persist metadata only', () async {
    final c = air.AirlinkController();
    await c.saveProfile(
      const Profile('Tower', 'https://backend.example', 'tower'),
    );
    final other = air.AirlinkController();
    await other.loadProfiles();
    expect(other.profiles.single.deviceId, 'tower');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('airlink.profiles.v1'), isNot(contains('token')));
    c.dispose();
    other.dispose();
  });

  test('polling does not overlap, rejects malformed snapshots, clears session on disconnect', () async {
    final pending = Completer<http.Response>();
    var count = 0;
    final c = air.AirlinkController(
      client: MockClient((request) {
        count++;
        expect(request.headers['Authorization'], 'Bearer session-secret');
        expect(request.followRedirects, false);
        return pending.future;
      }),
    );
    c.setInterval(0);
    final connection = c.connect(
      const Profile('Tower', 'https://backend.example', 'tower'),
      'session-secret',
    );
    await c.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(count, 1);
    pending.complete(http.Response('{}', 200));
    await connection;
    expect(c.state, air.ConnectionState.error);
    expect(c.snapshot, isNull);
    c.disconnect();
    expect(c.state, air.ConnectionState.disconnected);
    c.dispose();
  });

  test('late replies cannot replace demo or disconnected state', () async {
    final pending = Completer<http.Response>();
    final c = air.AirlinkController(client: MockClient((_) => pending.future));
    c.setInterval(0);
    final connection = c.connect(
      const Profile('Tower', 'https://backend.example', 'tower'),
      'secret',
    );
    c.startDemo(true);
    pending.complete(http.Response('{}', 200));
    await connection;
    expect(c.demo, true);
    expect(c.snapshot!.ports.length, 12);
    c.dispose();
  });

  test(
    'live failures retain stale values, unsupported replacement clears them',
    () async {
      var status = 200;
      final json = demoSnapshot(false, 1, DateTime.now().toUtc()).json;
      json.addAll({'mode': 'live', 'device_id': 'tower'});
      json['device']['verified'] = true;
      final c = air.AirlinkController(
        client: MockClient(
          (_) async => http.Response(jsonEncode(json), status),
        ),
      );
      c.setInterval(0);
      await c.connect(
        const Profile('Tower', 'https://backend.example', 'tower'),
        'secret',
      );
      expect(c.state, air.ConnectionState.connected);
      status = 503;
      await c.refresh();
      expect(c.state, air.ConnectionState.error);
      expect(c.snapshot, isNotNull);
      status = 422;
      await c.refresh();
      expect(c.state, air.ConnectionState.unsupported);
      expect(c.snapshot, isNull);
      c.dispose();
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('connection and all dashboard sections fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = air.AirlinkController();
      c.setInterval(0);
      await tester.pumpWidget(AirlinkApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Connect to your backend'), findsOneWidget);
      c.startDemo(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('DEMO MODE'), findsOneWidget);
      expect(find.text('Network overview'), findsOneWidget);
      for (final section in [
        'Ports',
        'Traffic',
        'PoE',
        'System',
        'Updates',
        'Network',
        'Overview',
      ]) {
        await tester.tap(find.text(section).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      c.startDemo(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('CRS112-8P-4S-IN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
