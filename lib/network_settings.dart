import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_config.dart';

class NetworkSettings extends StatefulWidget {
  final String draftId;
  final bool demo;
  const NetworkSettings({super.key, required this.draftId, required this.demo});
  @override
  State<NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends State<NetworkSettings> {
  final iface = TextEditingController(),
      address = TextEditingController(),
      prefix = TextEditingController(),
      gateway = TextEditingController(),
      dns = TextEditingController();
  String mode = 'dhcp';
  String? error;
  bool loading = true, saving = false, saved = false;
  NetworkConfig? reviewed;
  String get storageKey => 'airlink.network-draft.v1.${widget.draftId}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(storageKey);
      if (!mounted) return;
      if (text != null) {
        if (text.length > 4096) throw const FormatException();
        final value = NetworkConfig.fromJson(
          jsonDecode(text) as Map<String, dynamic>,
        );
        mode = value.mode;
        iface.text = value.interfaceName;
        address.text = value.address;
        prefix.text = value.prefix?.toString() ?? '';
        gateway.text = value.gateway;
        dns.text = value.dns.join(', ');
        reviewed = value;
        saved = true;
      }
    } catch (_) {
      if (mounted) error = 'Saved draft could not be loaded. Enter settings again; no device was changed.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void changed() => setState(() {
    reviewed = null;
    saved = false;
    error = null;
  });

  Future<void> save() async {
    setState(() {
      error = null;
      reviewed = null;
      saved = false;
    });
    NetworkConfig value;
    try {
      value = NetworkConfig.validate(
        mode: mode,
        interfaceName: iface.text,
        address: address.text,
        prefix: prefix.text,
        gateway: gateway.text,
        dns: dns.text,
      );
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    setState(() => saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, jsonEncode(value.toJson()))) {
        throw StateError('Draft storage failed');
      }
      if (mounted) {
        setState(() {
          reviewed = value;
          saved = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Draft could not be saved locally. No device was changed.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [iface, address, prefix, gateway, dns]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String label,
    String key,
    TextEditingController controller,
    String hint,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      key: Key(key),
      controller: controller,
      onChanged: (_) => changed(),
      maxLength: key == 'network-dns' ? 47 : 64,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Management IP address',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            widget.demo
                ? 'DEMO · Local network draft only'
                : 'Local network draft · Not applied to the device',
            style: const TextStyle(color: Colors.orangeAccent),
          ),
          const SizedBox(height: 8),
          const Text(
            'Current device IP and DHCP state: Unavailable. '
            'This screen prepares settings for future AirLink firmware. '
            'A device-side network configuration service is not implemented.',
          ),
          const SizedBox(height: 16),
          if (loading)
            const LinearProgressIndicator()
          else
            AbsorbPointer(
              absorbing: saving,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    key: const Key('network-mode'),
                    segments: const [
                      ButtonSegment(
                        value: 'dhcp',
                        label: Text('DHCP'),
                        icon: Icon(Icons.autorenew),
                      ),
                      ButtonSegment(
                        value: 'static',
                        label: Text('Static IPv4'),
                        icon: Icon(Icons.edit_outlined),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (value) {
                      changed();
                      setState(() => mode = value.single);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    mode == 'dhcp'
                        ? 'Obtain the address, gateway and DNS automatically from a DHCP server.'
                        : 'Enter a fixed address for the management network. IPv4 LAN prefixes /1–/30 are supported.',
                  ),
                  field(
                    'Management interface',
                    'network-interface',
                    iface,
                    'Example: bridge-mgmt',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Interface names are not discovered or verified yet. Enter the intended bridge or VLAN interface.',
                  ),
                  if (mode == 'static') ...[
                    field(
                      'IPv4 address',
                      'network-address',
                      address,
                      'Example: 192.168.88.2',
                    ),
                    field(
                      'Subnet prefix length',
                      'network-prefix',
                      prefix,
                      'Example: 24 (255.255.255.0)',
                    ),
                    field(
                      'Gateway (optional)',
                      'network-gateway',
                      gateway,
                      'Example: 192.168.88.1',
                    ),
                    field(
                      'DNS servers (optional, comma separated)',
                      'network-dns',
                      dns,
                      'Example: 192.168.88.1',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Blank gateway means no default route. Blank DNS means no configured resolver.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Changing the management address can disconnect this session. '
                    'DHCP requires a reachable server; static addressing requires an unused address. '
                    'Reachability and address conflicts are not checked by this draft editor.',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        key: const Key('network-save'),
                        onPressed: saving ? null : save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          saving ? 'Saving…' : 'Validate & save draft',
                        ),
                      ),
                      OutlinedButton(
                        key: const Key('network-apply'),
                        onPressed: null,
                        child: const Text('Apply to device — unavailable'),
                      ),
                    ],
                  ),
                  if (saved && reviewed != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Saved on this computer/browser for this device profile. No device settings changed.',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      const JsonEncoder.withIndent('  ')
                          .convert(reviewed!.toJson()),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
