import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum ConnectionState { disconnected, loading, connected, error, unsupported }

class AirlinkController extends ChangeNotifier {
  final http.Client client;
  AirlinkController({http.Client? client}) : client = client ?? http.Client();
  List<Profile> profiles = [];
  Snapshot? snapshot;
  Profile? profile;
  bool demo = false, smallDemo = false, busy = false;
  bool _disposed = false;
  bool controlBusy = false;
  bool checkingUpdates = false;
  Json? firmwareCheck;
  String? firmwareCheckError;
  final Map<String, String> _demoPoeModes = {};
  int interval = 5, _epoch = 0, _tick = 0;
  String? error;
  String _token = '';
  Completer<void>? _abort;

  Future<http.Response> _get(
    Uri uri,
    String token,
    int seconds, {
    String method = 'GET',
    Json? body,
  }) async {
    final abort = Completer<void>();
    _abort = abort;
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..headers['Authorization'] = 'Bearer $token'
          ..followRedirects = false;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await (() async {
        final response = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 2000000) {
            throw const FormatException(
              'Backend response exceeds the allowed size.',
            );
          }
        }
        return http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
        );
      })().timeout(Duration(seconds: seconds));
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
    }
  }

  ConnectionState state = ConnectionState.disconnected;
  Timer? _timer;
  final Map<String, List<TrafficPoint>> history = {};
  DateTime? _lastPoint;

  Future<void> loadProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      profiles =
          (jsonDecode(prefs.getString('airlink.profiles.v1') ?? '[]') as List)
              .map((j) => Profile.fromJson(Map<String, dynamic>.from(j)))
              .toList();
    } catch (_) {
      error = 'Saved profiles could not be loaded.';
    }
    _notify();
  }

  Future<void> saveProfile(Profile p) async {
    validateBackend(p.url);
    profiles.removeWhere(
      (old) => old.url == p.url && old.deviceId == p.deviceId,
    );
    profiles.add(p);
    await _persist();
  }

  Future<void> removeProfile(Profile p) async {
    profiles.remove(p);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'airlink.profiles.v1',
        jsonEncode(profiles.map((p) => p.toJson()).toList()),
      );
    } catch (_) {
      error = 'Profile storage failed. This connection can still be used for this session.';
    }
    _notify();
  }

  Future<List<Json>> discover(String url, String token) async {
    final uri = validateBackend(url).replace(path: '/api/v1/devices');
    final response = await _get(uri, token, 15);
    if (response.statusCode != 200) {
      throw Exception(_httpError(response.statusCode));
    }
    return ((jsonDecode(response.body) as Json)['devices'] as List)
        .cast<Json>();
  }

  void startDemo(bool small) {
    disconnect();
    demo = true;
    smallDemo = small;
    final now = DateTime.now().toUtc();
    for (var i = 0; i < 30; i++) {
      snapshot = demoSnapshot(
        small,
        i,
        now.subtract(
          Duration(seconds: (29 - i) * (interval > 0 ? interval : 5)),
        ),
      );
      _record();
    }
    _tick = 30;
    state = ConnectionState.connected;
    _notify();
    _schedule();
  }

  Future<void> connect(Profile p, String token) async {
    validateBackend(p.url);
    disconnect();
    profile = p;
    _token = token;
    state = ConnectionState.loading;
    await refresh();
  }

  void disconnect() {
    _epoch++;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    _timer?.cancel();
    demo = false;
    busy = false;
    controlBusy = false;
    checkingUpdates = false;
    firmwareCheck = null;
    firmwareCheckError = null;
    _demoPoeModes.clear();
    _token = '';
    profile = null;
    snapshot = null;
    error = null;
    history.clear();
    _lastPoint = null;
    state = ConnectionState.disconnected;
    _notify();
  }

  Future<void> refresh() async {
    if (busy || controlBusy || checkingUpdates || (!demo && profile == null)) {
      return;
    }
    _timer?.cancel();
    final epoch = _epoch;
    busy = true;
    _notify();
    try {
      if (demo) {
        snapshot = demoSnapshot(smallDemo, _tick++, DateTime.now().toUtc());
        _applyDemoPoe();
      } else {
        final p = profile!;
        final uri = validateBackend(p.url).replace(
          pathSegments: ['api', 'v1', 'devices', p.deviceId, 'snapshot'],
        );
        final response = await _get(uri, _token, 75);
        if (epoch != _epoch) return;
        if (response.statusCode != 200) {
          if (response.statusCode == 422) {
            snapshot = null;
            history.clear();
            state = ConnectionState.unsupported;
          }
          throw Exception(_httpError(response.statusCode));
        }
        snapshot = Snapshot.live(jsonDecode(response.body) as Json, p.deviceId);
      }
      error = snapshot!.stale
          ? 'Readings are stale. Backend is reconnecting; last successful values are shown.'
          : null;
      state = snapshot!.stale
          ? ConnectionState.error
          : ConnectionState.connected;
      if (!snapshot!.stale) {
        _record();
      } else {
        _gap();
      }
    } catch (e) {
      if (epoch != _epoch) return;
      if (state != ConnectionState.unsupported) state = ConnectionState.error;
      _gap();
      error = e is TimeoutException
          ? 'Connection timed out. Check the backend and network.'
          : e is FormatException
          ? e.message
          : e.toString().startsWith('Exception:')
          ? e.toString().replaceFirst('Exception: ', '')
          : 'Unable to reach the backend. Check TLS, address and network.';
    } finally {
      if (epoch == _epoch && !_disposed) {
        busy = false;
        _notify();
        _schedule();
      }
    }
  }

  static String _httpError(int status) => switch (status) {
    401 =>
      'Authentication failed. Reconnect with a valid backend access token.',
    404 => 'Saved device profile was not found on this backend.',
    422 => 'Unsupported device, model mismatch or unverified physical port inventory.',
    503 =>
      'Device unavailable or collection in progress. Retrying automatically.',
    400 => 'Backend requires HTTPS for this connection.',
    _ => 'Backend request failed (HTTP $status).',
  };

  bool canControlPoe(Json port) =>
      !busy &&
      !controlBusy &&
      !checkingUpdates &&
      state == ConnectionState.connected &&
      snapshot != null &&
      !snapshot!.stale &&
      DateTime.now().difference(snapshot!.updated).inSeconds < 60 &&
      port['kind'] == 'Ethernet' &&
      (demo ||
          (snapshot!.json['controls']?['poe_ports'] as List? ?? []).contains(
            port['default_name'],
          ));

  int beginPoe(Json port) {
    if (!canControlPoe(port)) {
      throw StateError(
        'Refresh or enable this port in the backend PoE allowlist.',
      );
    }
    _timer?.cancel();
    controlBusy = true;
    _notify();
    return _epoch;
  }

  Future<void> checkFirmware() async {
    if (busy || controlBusy || checkingUpdates || (!demo && profile == null)) {
      return;
    }
    final epoch = _epoch;
    _timer?.cancel();
    checkingUpdates = true;
    firmwareCheckError = null;
    _notify();
    try {
      if (demo) {
        firmwareCheck = {
          'status': 'demo_no_online_check',
          'mode': 'demo',
          'checked_at': DateTime.now().toUtc().toIso8601String(),
          'last_success_at': null,
          'stale': false,
          'installation_allowed': false,
          'signature_verified': false,
          'candidate': null,
          'board': {...snapshot!.device, 'airlink_version': null},
        };
      } else {
        final p = profile!;
        final response = await _get(
          validateBackend(p.url).replace(
            pathSegments: [
              'api',
              'v1',
              'devices',
              p.deviceId,
              'firmware',
              'check',
            ],
          ),
          _token,
          90,
        );
        if (epoch != _epoch) return;
        if (response.statusCode != 200) {
          throw StateError(
            response.statusCode == 409
                ? 'A fresh verified board snapshot is required. Wait for monitoring and try again.'
                : _httpError(response.statusCode),
          );
        }
        final data = jsonDecode(response.body);
        const statuses = {
          'check_in_progress',
          'catalog_unavailable',
          'catalog_stale',
          'no_published_firmware',
          'board_identity_incomplete',
          'no_matching_firmware',
          'installed_version_unavailable',
          'newer_metadata_available',
          'no_newer_metadata',
        };
        bool timeValue(dynamic t) =>
            t == null || (t is String && DateTime.tryParse(t) != null);
        if (data is! Json ||
            data['schema_version'] != 1 ||
            data['mode'] != 'live' ||
            data['device_id'] != p.deviceId ||
            !statuses.contains(data['status']) ||
            data['board'] is! Json ||
            data['board']['model'] != snapshot?.device['model'] ||
            data['board']['architecture'] != snapshot?.device['architecture'] ||
            data['installation_allowed'] != false ||
            data['signature_verified'] != false ||
            data['stale'] is! bool ||
            data['checked_at'] is! String ||
            !timeValue(data['checked_at']) ||
            !timeValue(data['last_success_at']) ||
            (data['candidate'] != null &&
                (data['candidate'] is! Json ||
                    data['candidate']['version'] is! String))) {
          throw const FormatException(
            'Invalid update-check response. Installation remains disabled.',
          );
        }
        firmwareCheck = data;
      }
    } catch (e) {
      if (epoch == _epoch) {
        firmwareCheckError = e is StateError
            ? e.message.toString()
            : e is FormatException
            ? e.message
            : 'Online check failed. Check backend connectivity and TLS.';
      }
    } finally {
      if (epoch == _epoch && !_disposed) {
        checkingUpdates = false;
        _notify();
        _schedule();
      }
    }
  }

  void _checkControl(int epoch) {
    if (_disposed ||
        epoch != _epoch ||
        !controlBusy ||
        (!demo && profile == null)) {
      throw StateError(
        'Connection changed. Close this dialog and start again.',
      );
    }
  }

  Future<Json> _poeRequest(
    String endpoint,
    String token,
    Json body,
    int epoch,
  ) async {
    _checkControl(epoch);
    final p = profile!;
    final response = await _get(
      validateBackend(p.url).replace(
        pathSegments: ['api', 'v1', 'devices', p.deviceId, 'poe', endpoint],
      ),
      token,
      75,
      method: 'POST',
      body: body,
    );
    _checkControl(epoch);
    if (response.statusCode != 200) {
      throw StateError(switch (response.statusCode) {
        401 || 403 => 'PoE permission denied. Check the separate operator token and backend port allowlist.',
        409 => 'Device busy, configuration changed, or confirmation expired/used. Close and review again.',
        422 => 'Device identity, port or PoE configuration is unsupported. No new action was accepted.',
        502 => 'Outcome unknown: PoE may have changed. Refresh and check the device before trying again.',
        503 => 'Device preflight unavailable. No write was sent.',
        _ =>
          'PoE request failed (HTTP ${response.statusCode}). Check current configuration before retrying.',
      });
    }
    return jsonDecode(response.body) as Json;
  }

  Future<Json> preparePoe(
    Json port,
    String mode,
    String token,
    int epoch,
  ) async {
    _checkControl(epoch);
    if (!{'auto-on', 'off'}.contains(mode)) {
      throw StateError('Unsupported PoE mode.');
    }
    if (demo) {
      return {
        'confirmation_id': 'demo',
        'port': port['default_name'],
        'name': port['name'],
        'previous_mode': port['poe']['configuration_mode'],
        'requested_mode': mode,
        'expires_in_seconds': 60,
        'device_label': snapshot!.device['identity'],
      };
    }
    final result = await _poeRequest('prepare', token, {
      'default_name': port['default_name'],
      'expected_name': port['name'],
      'mode': mode,
    }, epoch);
    if (result['confirmation_id'] is! String ||
        result['port'] != port['default_name'] ||
        result['name'] != port['name'] ||
        result['requested_mode'] != mode ||
        result['device_id'] != profile!.deviceId) {
      throw const FormatException(
        'Invalid PoE confirmation response. No write sent.',
      );
    }
    return result;
  }

  Future<String> commitPoe(Json prepared, String token, int epoch) async {
    _checkControl(epoch);
    if (demo) {
      _demoPoeModes[prepared['port'] as String] =
          prepared['requested_mode'] as String;
      _applyDemoPoe();
      _notify();
      return 'DEMO: PoE ${prepared['requested_mode']} simulated. No device was changed.';
    }
    // The command may interrupt connectivity. Old measurements must become stale
    // even when the HTTP response is lost. Never automatically retry a POST.
    snapshot = Snapshot({...snapshot!.json, 'stale': true});
    _notify();
    try {
      final result = await _poeRequest('commit', token, {
        'confirmation_id': prepared['confirmation_id'],
        'confirmed': true,
      }, epoch);
      if (result['status'] != 'configuration_verified' ||
          result['configuration_mode'] != prepared['requested_mode'] ||
          result['port'] != prepared['port'] ||
          result['device_id'] != profile!.deviceId) {
        throw const FormatException(
          'Unexpected control response. Refresh before retrying.',
        );
      }
      return 'PoE ${result['configuration_mode']} setting verified. Refreshing power readings.';
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'Outcome unknown: connection lost or invalid reply. PoE may have changed. Refresh before retrying.',
      );
    }
  }

  Future<void> endPoe(int epoch) async {
    if (_disposed || epoch != _epoch) return;
    controlBusy = false;
    _notify();
    await refresh();
  }

  void _applyDemoPoe() {
    for (final p in snapshot!.ports) {
      final mode = _demoPoeModes[p['default_name']];
      if (mode == null) continue;
      p['poe']['configuration_mode'] = mode;
      if (mode == 'off') {
        p['poe'].addAll({
          'status': 'powered-off',
          'voltage_v': 0.0,
          'current_a': 0.0,
          'power_w': 0.0,
        });
      }
    }
  }

  void _gap() {
    for (final list in history.values) {
      if (list.isNotEmpty && (list.last.rx != null || list.last.tx != null)) {
        list.add(TrafficPoint(DateTime.now().toUtc(), null, null));
        if (list.length > 120) list.removeAt(0);
      }
    }
  }

  void _record() {
    final s = snapshot!;
    final observed = s.ports
        .map((p) => p['counters_at'])
        .whereType<String>()
        .firstOrNull;
    if (observed == null) return;
    final time = DateTime.parse(observed);
    if (_lastPoint == time) return;
    _lastPoint = time;
    void add(String id, double? rx, double? tx) {
      final list = history.putIfAbsent(id, () => []);
      list.add(TrafficPoint(time, rx, tx));
      if (list.length > 120) list.removeAt(0);
    }

    add('all', s.total('rx_mbps'), s.total('tx_mbps'));
    for (final p in s.ports) {
      add(
        p['id'] as String,
        (p['rx_mbps'] as num?)?.toDouble(),
        (p['tx_mbps'] as num?)?.toDouble(),
      );
    }
  }

  void setInterval(int seconds) {
    interval = seconds;
    _schedule();
    _notify();
  }

  void _schedule() {
    _timer?.cancel();
    if (interval > 0 &&
        !_disposed &&
        !controlBusy &&
        !checkingUpdates &&
        (demo || profile != null)) {
      _timer = Timer(Duration(seconds: interval), refresh);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    _token = '';
    _timer?.cancel();
    client.close();
    super.dispose();
  }
}
