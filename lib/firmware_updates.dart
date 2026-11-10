import 'package:flutter/material.dart';

import 'firmware_manifest.dart';
import 'models.dart';

class FirmwareUpdates extends StatefulWidget {
  final Snapshot snapshot;
  final bool demo, stale;
  const FirmwareUpdates({
    super.key,
    required this.snapshot,
    required this.demo,
    required this.stale,
  });

  @override
  State<FirmwareUpdates> createState() => _FirmwareUpdatesState();
}

class _FirmwareUpdatesState extends State<FirmwareUpdates> {
  final input = TextEditingController();
  FirmwareManifest? manifest;
  String? error;
  DateTime? reviewedAt;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void review() {
    setState(() {
      manifest = null;
      reviewedAt = null;
      error = null;
      try {
        manifest = FirmwareManifest.parse(input.text);
        reviewedAt = DateTime.now();
      } on FormatException catch (e) {
        error = e.message;
      }
    });
  }

  Widget card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final issues =
        manifest?.compatibilityIssues(
          snapshot,
          demo: widget.demo,
          stale: widget.stale,
        ) ??
        <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card('AirLink firmware updates', [
          const Text(
            'Installation unavailable',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This section is for future AirLink firmware running on the switch. '
            'No verified installable image or device-side updater is available for either supported model.',
          ),
          const SizedBox(height: 12),
          Text('Model: ${reading(snapshot.device['model'])}'),
          Text('Architecture: ${reading(snapshot.device['architecture'])}'),
          Text(
            'Reported board revision: ${reading(snapshot.device['board_revision'])}',
          ),
          Text(
            'RouterOS version${widget.demo ? ' (simulated)' : ''}: ${reading(snapshot.system['routeros_version'])}',
          ),
          const Text(
            'Installed AirLink firmware: Unavailable — no AirLink firmware agent',
          ),
          Text(
            '${widget.stale ? 'STALE · ' : ''}Last device snapshot: ${snapshot.updated.toLocal()}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Desktop/web application downloads are not switch firmware. '
            'This screen does not upgrade RouterOS or RouterBOOT.',
          ),
        ]),
        card('Review package metadata', [
          const Text(
            'Paste a draft AirLink firmware manifest JSON. Review runs locally; '
            'it does not upload an image, contact the switch or change settings. '
            'Format: firmware/UPDATE-PROTOCOL.md in the project.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('firmware-manifest'),
            controller: input,
            minLines: 4,
            maxLines: 8,
            maxLength: 16384,
            decoration: const InputDecoration(
              labelText: 'Manifest JSON',
              hintText: '{ "schema": "airlink.firmware-manifest.draft1", … }',
            ),
            onChanged: (_) => setState(() {
              manifest = null;
              error = null;
              reviewedAt = null;
            }),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('firmware-review'),
            onPressed: review,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review metadata'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          if (manifest != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Metadata reviewed — installation still blocked',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Reviewed locally: $reviewedAt'),
            Text('Declared version: ${manifest!.fields['version']}'),
            Text(
              'Declared image size: ${manifest!.fields['size_bytes']} bytes',
            ),
            SelectableText(
              'Declared SHA-256 (not checked against an image): ${manifest!.fields['sha256']}',
            ),
            const SizedBox(height: 8),
            if (issues.isEmpty)
              const Text(
                'Declared target matches the reported identity. This does not establish hardware compatibility.',
              )
            else
              for (final issue in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $issue'),
                ),
            const Text(
              'Image contents, digest, publisher signature and upgrade safety are NOT verified.',
            ),
          ],
        ]),
        card('Required before installation can be enabled', [
          for (final item in const [
            'Verified exact-board support, device tree, flash layout and bootloader preservation.',
            'Tested Ethernet/switch, SFP, PoE, watchdog and temperature drivers.',
            'Verified root filesystem and image packaging for this board revision.',
            'Successful RAM boot and recovery tests with local console access.',
            'Trusted signing keys, image verification and an authenticated device-side update agent.',
            'Tested configuration migration, power-loss handling and recovery or rollback.',
            'Separate update permission, fresh identity checks and explicit confirmation of downtime.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $item'),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('firmware-install'),
            onPressed: null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Install firmware — unavailable'),
          ),
          const SizedBox(height: 8),
          const Text(
            'An eventual update will interrupt management and may interrupt forwarding and PoE. '
            'No reboot or flash operation is implemented here.',
          ),
        ]),
      ],
    );
  }
}
