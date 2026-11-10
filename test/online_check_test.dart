import 'dart:async';
import 'dart:convert';

import 'package:airlink_manager/controller.dart';
import 'package:airlink_manager/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Json snapshot() {
  final data = demoSnapshot(true, 0, DateTime.now().toUtc()).json;
  data.addAll({'mode': 'live', 'device_id': 'switch'});
  data['device']['verified'] = true;
  data['device']['board_revision'] = 'r2';
  return data;
}

Json result() => {
  'schema_version': 1,
  'mode': 'live',
  'device_id': 'switch',
  'status': 'no_published_firmware',
  'board': snapshot()['device'],
  'checked_at': DateTime.now().toUtc().toIso8601String(),
  'last_success_at': DateTime.now().toUtc().toIso8601String(),
  'stale': false,
  'installation_allowed': false,
  'signature_verified': false,
  'candidate': null,
};

void main() {
  test('demo online preview makes no board or internet request', () async {
    final c = AirlinkController(
      client: MockClient((_) => throw StateError('Unexpected network request')),
    );
    c.setInterval(0);
    c.startDemo(true);
    await c.checkFirmware();
    expect(c.firmwareCheck!['status'], 'demo_no_online_check');
    c.dispose();
  });

  test('online check uses backend auth and excludes monitoring, repeated checks and PoE', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final c = AirlinkController(
      client: MockClient((request) async {
        calls++;
        expect(request.url.host, 'backend.example');
        expect(request.headers['Authorization'], 'Bearer test-session-token');
        expect(request.followRedirects, false);
        if (request.url.path.endsWith('/snapshot')) {
          return http.Response(jsonEncode(snapshot()), 200);
        }
        expect(request.url.path, '/api/v1/devices/switch/firmware/check');
        return pending.future;
      }),
    )..setInterval(0);
    await c.connect(
      const Profile('Switch', 'https://backend.example', 'switch'),
      'test-session-token',
    );
    final check = c.checkFirmware();
    await Future<void>.delayed(Duration.zero);
    await c.refresh();
    await c.checkFirmware();
    expect(calls, 2);
    expect(c.checkingUpdates, true);
    expect(c.canControlPoe(c.snapshot!.ports.first), false);
    pending.complete(http.Response(jsonEncode(result()), 200));
    await check;
    expect(c.firmwareCheck!['status'], 'no_published_firmware');
    expect(c.checkingUpdates, false);
    c.dispose();
  });

  test('late online response cannot populate a new demo session', () async {
    final pending = Completer<http.Response>();
    final c = AirlinkController(
      client: MockClient(
        (request) async => request.url.path.endsWith('/snapshot')
            ? http.Response(jsonEncode(snapshot()), 200)
            : pending.future,
      ),
    )..setInterval(0);
    await c.connect(
      const Profile('Switch', 'https://backend.example', 'switch'),
      'token',
    );
    final check = c.checkFirmware();
    c.startDemo(false);
    pending.complete(http.Response(jsonEncode(result()), 200));
    await check;
    expect(c.firmwareCheck, isNull);
    expect(c.checkingUpdates, false);
    c.dispose();
  });

  test('API cannot authorize install; failed checks retain timestamped previous result', () async {
    var body = result();
    final c = AirlinkController(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/snapshot') ? snapshot() : body,
          ),
          200,
        ),
      ),
    )..setInterval(0);
    await c.connect(
      const Profile('Switch', 'https://backend.example', 'switch'),
      'token',
    );
    await c.checkFirmware();
    final previous = c.firmwareCheck;
    body = {...result(), 'installation_allowed': true};
    await c.checkFirmware();
    expect(c.firmwareCheck, same(previous));
    expect(c.firmwareCheckError, contains('Invalid update-check response'));
    c.disconnect();
    expect(c.firmwareCheck, isNull);
    c.dispose();
  });
}
