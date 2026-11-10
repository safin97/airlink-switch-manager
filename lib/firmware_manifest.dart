import 'dart:convert';

import 'models.dart';

/// A draft descriptor, not an image format, signature or installation authority.
class FirmwareManifest {
  final Json fields;
  FirmwareManifest._(this.fields);

  static const products = {
    'CRS112-8P-4S-IN': 'mipsbe',
    'CRS318-16P-2S+OUT': 'arm',
  };

  factory FirmwareManifest.parse(String text) {
    if (utf8.encode(text).length > 16384) {
      throw const FormatException('Manifest exceeds 16 KiB.');
    }
    dynamic value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Paste a valid JSON object.');
    }
    const keys = {
      'schema',
      'product',
      'architecture',
      'board_revision',
      'version',
      'image_type',
      'sha256',
      'size_bytes',
    };
    if (value is! Json ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const FormatException(
        'Expected exactly: schema, product, architecture, board_revision, '
        'version, image_type, sha256, size_bytes. See the firmware update guide.',
      );
    }
    if (value['schema'] != 'airlink.firmware-manifest.draft1' ||
        value['image_type'] != 'sysupgrade') {
      throw const FormatException(
        'Unsupported descriptor schema or image type.',
      );
    }
    if (!products.containsKey(value['product']) ||
        products[value['product']] != value['architecture']) {
      throw const FormatException(
        'Unsupported product or incorrect architecture.',
      );
    }
    for (final key in ['board_revision', 'version']) {
      if (value[key] is! String ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$').hasMatch(value[key])) {
        throw FormatException(
          '$key must be an explicit value (1–64 characters).',
        );
      }
    }
    if (value['sha256'] is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value['sha256']) ||
        value['size_bytes'] is! int ||
        value['size_bytes'] <= 0 ||
        value['size_bytes'] > 4294967295) {
      throw const FormatException(
        'Expected a SHA-256 hex digest and a positive image size of at most 4 GiB minus one byte.',
      );
    }
    return FirmwareManifest._(value);
  }

  /// Re-evaluated against the current snapshot; never authorizes a write.
  List<String> compatibilityIssues(
    Snapshot snapshot, {
    required bool demo,
    required bool stale,
  }) {
    final issues = <String>[];
    if (demo) {
      issues.add('Demo identity only; no physical device is connected.');
    }
    if (stale) {
      issues.add(
        'Device readings are stale. Refresh before assessing identity.',
      );
    }
    if (snapshot.device['verified'] != true) {
      issues.add('Device identity has not been verified by the backend.');
    }
    for (final key in ['model', 'architecture', 'board_revision']) {
      final actual = snapshot.device[key];
      final expected = fields[key == 'model' ? 'product' : key];
      if (actual == null || actual == '') {
        issues.add('$key is unavailable; compatibility cannot be established.');
      } else if (actual != expected) {
        issues.add('$key mismatch: device $actual; manifest $expected.');
      }
    }
    return issues;
  }
}
