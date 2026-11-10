import 'dart:math' as math;

typedef Json = Map<String, dynamic>;

String reading(dynamic value, [String unit = '', int decimals = 1]) =>
    value == null
    ? 'Unavailable'
    : '${value is num ? value.toStringAsFixed(decimals) : value}${unit.isEmpty ? '' : ' $unit'}';

String clockTime(DateTime? time) {
  if (time == null) return 'Never';
  final t = time.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class Profile {
  final String label, url, deviceId;
  const Profile(this.label, this.url, this.deviceId);
  Json toJson() => {'label': label, 'url': url, 'deviceId': deviceId};
  factory Profile.fromJson(Json j) => Profile(
    j['label'] as String,
    j['url'] as String,
    j['deviceId'] as String,
  );
}

Uri validateBackend(String text) {
  final uri = Uri.parse(text.trim());
  final local = {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  if (!uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.scheme != 'https' && !(uri.scheme == 'http' && local))) {
    throw const FormatException(
      'Use an HTTPS origin, or HTTP on localhost for development.',
    );
  }
  return uri.replace(path: '');
}

class Snapshot {
  final Json json;
  Snapshot(this.json);
  factory Snapshot.live(Json j, String deviceId) {
    if (j['schema_version'] != 1 ||
        j['mode'] != 'live' ||
        j['device_id'] != deviceId ||
        j['ports'] is! List ||
        j['device'] is! Map ||
        j['system'] is! Map ||
        j['device']['verified'] != true ||
        j['last_success_at'] is! String ||
        DateTime.tryParse(j['last_success_at'] as String) == null) {
      throw const FormatException('Invalid or unsupported backend response.');
    }
    bool numeric(dynamic v) => v == null || (v is num && v.isFinite);
    bool timestamp(dynamic v) =>
        v == null || (v is String && DateTime.tryParse(v) != null);
    final sys = j['system'] as Map;
    final ports = j['ports'] as List;
    final warnings = j['warnings'];
    final controls = j['controls'];
    if (controls != null &&
        (controls is! Map ||
            controls['poe_ports'] is! List ||
            !(controls['poe_ports'] as List).every(
              (p) => p is String && RegExp(r'^ether[1-9][0-9]*$').hasMatch(p),
            ))) {
      throw const FormatException('Invalid PoE control capabilities.');
    }
    if (sys['temperatures'] is! List ||
        !(sys['temperatures'] as List).every(
          (t) => t is Map && t['name'] is String && numeric(t['celsius']),
        ) ||
        ![
          'cpu_percent',
          'free_memory_bytes',
          'total_memory_bytes',
        ].every((k) => numeric(sys[k])) ||
        warnings is! List ||
        !warnings.every(
          (w) => w is Map && w['section'] is String && w['code'] is String,
        ) ||
        ports.isEmpty ||
        !ports.every(
          (p) =>
              p is Json &&
              [
                'id',
                'name',
                'default_name',
                'kind',
              ].every((k) => p[k] is String) &&
              [
                'speed_mbps',
                'rx_mbps',
                'tx_mbps',
              ].every((k) => numeric(p[k])) &&
              [
                'enabled',
                'full_duplex',
              ].every((k) => p[k] == null || p[k] is bool) &&
              ['observed_at', 'counters_at'].every((k) => timestamp(p[k])) &&
              p['poe'] is Map &&
              [
                'voltage_v',
                'current_a',
                'power_w',
              ].every((k) => numeric(p['poe'][k])) &&
              timestamp(p['poe']['observed_at']),
        )) {
      throw const FormatException(
        'Incomplete or malformed telemetry response.',
      );
    }
    return Snapshot(j);
  }
  List<Json> get ports => (json['ports'] as List).cast<Json>();
  Json get system => json['system'] as Json;
  Json get device => json['device'] as Json;
  bool get stale => json['stale'] == true;
  DateTime get updated => DateTime.parse(json['last_success_at'] as String);
  List<dynamic> get warnings => json['warnings'] as List? ?? [];
  double? total(String key) {
    final values = ports.map((p) => p[key]);
    if (values.isEmpty || values.any((v) => v is! num)) return null;
    return values.fold<double>(0, (sum, v) => sum + (v as num).toDouble());
  }
}

class TrafficPoint {
  final DateTime time;
  final double? rx, tx;
  TrafficPoint(this.time, this.rx, this.tx);
}

Snapshot demoSnapshot(bool small, int tick, DateTime time) {
  final copper = small ? 8 : 16;
  final count = small ? 12 : 18;
  final ports = List<Json>.generate(count, (i) {
    final fiber = i >= copper;
    final active = i % 5 != 3 && i != 7;
    final rx = active
        ? 14 + 11 * math.sin(tick * .24 + i).abs() + (fiber ? 210 : 0)
        : 0.0;
    final tx = active
        ? 7 + 8 * math.cos(tick * .19 + i).abs() + (fiber ? 90 : 0)
        : 0.0;
    final name = fiber
        ? '${small ? 'sfp' : 'sfp-sfpplus'}${i - copper + 1}'
        : 'ether${i + 1}';
    return {
      'id': '*${(i + 1).toRadixString(16)}',
      'name': name,
      'default_name': name,
      'kind': fiber ? (small ? 'SFP' : 'SFP+') : 'Ethernet',
      'enabled': i != 7,
      'link': active ? 'link-ok' : 'no-link',
      'speed_mbps': active ? (fiber && !small ? 10000 : 1000) : null,
      'full_duplex': active ? true : null,
      'rx_bytes': 128000000 + tick * 3000000 + i * 1000000,
      'tx_bytes': 64000000 + tick * 1500000 + i * 800000,
      'rx_mbps': rx,
      'tx_mbps': tx,
      'counter_reset': false,
      'observed_at': time.toIso8601String(),
      'counters_at': time.toIso8601String(),
      'poe': {
        'configuration_mode': fiber ? null : 'auto-on',
        'status': fiber ? null : (active ? 'powered-on' : 'waiting-for-load'),
        'voltage_v': !fiber && active ? 48.2 : null,
        'current_a': !fiber && active ? .16 + (i % 3) * .05 : null,
        'power_w': !fiber && active ? 7.7 + (i % 3) * 2.4 : null,
        'observed_at': fiber ? null : time.toIso8601String(),
      },
    };
  });
  return Snapshot({
    'schema_version': 1,
    'mode': 'demo',
    'status': 'connected',
    'stale': false,
    'last_success_at': time.toIso8601String(),
    'ports': ports,
    'warnings': [],
    'device': {
      'model': small ? 'CRS112-8P-4S-IN' : 'CRS318-16P-2S+OUT',
      'identity': small ? 'Office switch' : 'Tower switch',
      'verified': false,
      'architecture': small ? 'mipsbe' : 'arm',
    },
    'system': {
      'cpu_percent': 12 + 4 * math.sin(tick * .1).abs(),
      'free_memory_bytes': (small ? 82 : 174) * 1048576,
      'total_memory_bytes': (small ? 128 : 256) * 1048576,
      'uptime': '12d 08:42:16',
      'routeros_version': '7.x · simulated',
      'temperatures': [
        {'name': 'cpu-temperature', 'celsius': 42.0},
      ],
      'observed_at': time.toIso8601String(),
      'health_at': time.toIso8601String(),
    },
  });
}
