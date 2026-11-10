import 'package:flutter/material.dart' hide ConnectionState;

import 'controller.dart';
import 'models.dart';
import 'dashboard.dart';

const navy = Color(0xFF091321);
const panel = Color(0xFF101F31);
const teal = Color(0xFF43E0BE);
const muted = Color(0xFF8DA3B9);
const line = Color(0xFF23354B);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AirlinkApp());
}

class AirlinkApp extends StatefulWidget {
  final AirlinkController? controller;
  const AirlinkApp({super.key, this.controller});
  @override
  State<AirlinkApp> createState() => _AirlinkAppState();
}

class _AirlinkAppState extends State<AirlinkApp> {
  late final AirlinkController controller =
      widget.controller ?? AirlinkController();
  @override
  void initState() {
    super.initState();
    controller.loadProfiles();
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AirLink · Switch Manager',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navy,
      colorScheme: const ColorScheme.dark(
        primary: teal,
        surface: panel,
        secondary: Color(0xFF6AA6FF),
      ),
      fontFamily: 'Arial',
      dividerColor: line,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: navy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: line),
        ),
      ),
    ),
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => controller.profile == null && !controller.demo
          ? ConnectionScreen(controller: controller)
          : Dashboard(controller: controller),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: teal.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(Icons.hub_outlined, color: teal, size: 27),
      ),
      const SizedBox(width: 12),
      const Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AirLink',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            Text(
              'SWITCH MANAGER',
              style: TextStyle(fontSize: 9, color: muted, letterSpacing: 2),
            ),
          ],
        ),
      ),
    ],
  );
}

class ConnectionScreen extends StatefulWidget {
  final AirlinkController controller;
  const ConnectionScreen({super.key, required this.controller});
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final url = TextEditingController(text: 'https://');
  final token = TextEditingController();
  List<Json> devices = [];
  String? selected, error;
  bool loading = false;
  Profile? saved;
  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> discover() async {
    setState(() {
      loading = true;
      error = null;
      devices = [];
      selected = null;
    });
    try {
      if (token.text.trim().isEmpty) {
        throw const FormatException('Enter a backend access token.');
      }
      final result = await widget.controller.discover(
        url.text,
        token.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        devices = result;
        selected = result.isEmpty ? null : result.first['id'] as String;
        if (result.isEmpty) error = 'No devices configured on this backend.';
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> connect() async {
    try {
      final endpoint = validateBackend(url.text).toString();
      if (token.text.trim().isEmpty) {
        throw const FormatException('Enter a backend access token.');
      }
      final id = saved?.deviceId ?? selected;
      if (id == null) return;
      final p = Profile(
        saved?.label ??
            devices.firstWhere((d) => d['id'] == id)['label'] as String,
        endpoint,
        id,
      );
      final secret = token.text.trim();
      await widget.controller.saveProfile(p);
      if (!mounted) return;
      token.clear();
      await widget.controller.connect(p, secret);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Check the HTTPS backend address and access token.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Brand(),
                const SizedBox(height: 56),
                const Text(
                  'Your network.\nIn clear view.',
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    height: 1.06,
                    letterSpacing: -1.8,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Read-only monitoring for your MikroTik PoE switches.',
                  style: TextStyle(color: muted, fontSize: 17),
                ),
                const SizedBox(height: 30),
                LayoutBuilder(
                  builder: (context, c) {
                    final connection = _connectionCard();
                    final profiles = _profilesCard();
                    return c.maxWidth > 760
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 6, child: connection),
                              const SizedBox(width: 24),
                              Expanded(flex: 5, child: profiles),
                            ],
                          )
                        : Column(
                            children: [
                              connection,
                              const SizedBox(height: 20),
                              profiles,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'netPower 16P  /  CRS318-16P-2S+OUT     •     CRS112-8P-4S-IN',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _connectionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect to your backend',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Router credentials remain on your backend. Use its access token here.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'https://airlink.example.com',
            ),
            onChanged: (_) => setState(() {
              saved = null;
              devices = [];
              selected = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: token,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend access token',
              helperText: 'Kept in memory for this session only',
            ),
          ),
          if (saved != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                'Saved device: ${saved!.label}',
                style: const TextStyle(color: teal),
              ),
            ),
          if (devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Device profile'),
                items: devices
                    .map(
                      (d) => DropdownMenuItem(
                        value: d['id'] as String,
                        child: Text(
                          d['label'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => selected = v),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: loading
                ? null
                : saved != null || selected != null
                ? connect
                : discover,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward, size: 18),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                loading
                    ? 'Connecting…'
                    : saved != null || selected != null
                    ? 'Connect & save profile'
                    : 'Find configured devices',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _profilesCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saved profiles',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              if (widget.controller.profiles.isEmpty)
                const Text(
                  'Your devices will appear here after connecting.',
                  style: TextStyle(color: muted),
                ),
              for (final p in widget.controller.profiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.router_outlined, color: teal),
                  title: Text(p.label),
                  subtitle: Text(p.url, overflow: TextOverflow.ellipsis),
                  onTap: () => setState(() {
                    saved = p;
                    url.text = p.url;
                    devices = [];
                    selected = null;
                    error = null;
                  }),
                  trailing: IconButton(
                    tooltip: 'Remove saved profile',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      widget.controller.removeProfile(p);
                      if (saved == p) setState(() => saved = null);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.science_outlined, color: teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Explore demo mode',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Simulated readings. No device connection or credentials needed.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: () => widget.controller.startDemo(false),
                    child: const Text('Demo · netPower 16P'),
                  ),
                  OutlinedButton(
                    onPressed: () => widget.controller.startDemo(true),
                    child: const Text('Demo · CRS112'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
