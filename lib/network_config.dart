import 'dart:math' as math;

import 'models.dart';

/// Local draft only. This is not a device configuration or a write command.
class NetworkConfig {
  final String mode, interfaceName, address, gateway;
  final int? prefix;
  final List<String> dns;

  NetworkConfig._(
    this.mode,
    this.interfaceName,
    this.address,
    this.prefix,
    this.gateway,
    this.dns,
  );

  static int ipv4(String text) {
    final parts = text.split('.');
    if (parts.length != 4 ||
        parts.any(
          (p) =>
              !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(p) ||
              int.parse(p) > 255,
        )) {
      throw const FormatException(
        'Enter an IPv4 address with four decimal octets (0–255).',
      );
    }
    final octets = parts.map(int.parse).toList();
    if (octets[0] == 0 || octets[0] == 127 || octets[0] >= 224) {
      throw const FormatException(
        'Use a unicast IPv4 address, not an unspecified, loopback or multicast address.',
      );
    }
    return octets.fold<int>(0, (value, octet) => value * 256 + octet);
  }

  factory NetworkConfig.validate({
    required String mode,
    required String interfaceName,
    String address = '',
    String prefix = '',
    String gateway = '',
    String dns = '',
  }) {
    final name = interfaceName.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$').hasMatch(name)) {
      throw const FormatException(
        'Enter a management interface name (1–64 letters, numbers, dot, dash, underscore or colon).',
      );
    }
    if (mode == 'dhcp') {
      return NetworkConfig._(mode, name, '', null, '', const []);
    }
    if (mode != 'static') {
      throw const FormatException('Choose DHCP or static IPv4.');
    }
    final ipText = address.trim(), gwText = gateway.trim();
    final ip = ipv4(ipText);
    final bits = int.tryParse(prefix.trim());
    if (bits == null ||
        bits < 1 ||
        bits > 30 ||
        !RegExp(r'^[0-9]{1,2}$').hasMatch(prefix.trim())) {
      throw const FormatException(
        'This LAN editor supports prefix lengths 1–30, for example 24.',
      );
    }
    final size = math.pow(2, 32 - bits).toInt();
    final network = ip ~/ size * size;
    final broadcast = network + size - 1;
    if (ip == network || ip == broadcast) {
      throw const FormatException(
        'The static address cannot be the subnet network or broadcast address.',
      );
    }
    if (gwText.isNotEmpty) {
      final gw = ipv4(gwText);
      if (gw <= network || gw >= broadcast || gw == ip) {
        throw const FormatException(
          'Gateway must be a different usable address in the same subnet.',
        );
      }
    }
    final servers = dns.trim().isEmpty
        ? <String>[]
        : dns.split(',').map((s) => s.trim()).toList();
    if (servers.length > 3 || servers.toSet().length != servers.length) {
      throw const FormatException(
        'Enter up to three distinct DNS IPv4 addresses, separated by commas.',
      );
    }
    for (final server in servers) {
      ipv4(server);
    }
    return NetworkConfig._(
      mode,
      name,
      ipText,
      bits,
      gwText,
      List.unmodifiable(servers),
    );
  }

  Json toJson() => {
    'schema': 'airlink.network-draft.v1',
    'mode': mode,
    'interface': interfaceName,
    if (mode == 'static') ...{
      'address': address,
      'prefix': prefix,
      'gateway': gateway,
      'dns': dns,
    },
  };

  factory NetworkConfig.fromJson(Json j) {
    if (j['schema'] != 'airlink.network-draft.v1' ||
        j['mode'] is! String ||
        j['interface'] is! String ||
        (j['mode'] == 'static' &&
            (j['address'] is! String ||
                j['prefix'] is! int ||
                j['gateway'] is! String ||
                j['dns'] is! List ||
                !(j['dns'] as List).every((v) => v is String)))) {
      throw const FormatException('Saved network draft is invalid.');
    }
    return NetworkConfig.validate(
      mode: j['mode'],
      interfaceName: j['interface'],
      address: j['mode'] == 'static' ? j['address'] : '',
      prefix: j['mode'] == 'static' ? '${j['prefix']}' : '',
      gateway: j['mode'] == 'static' ? j['gateway'] : '',
      dns: j['mode'] == 'static' ? (j['dns'] as List).join(',') : '',
    );
  }
}
