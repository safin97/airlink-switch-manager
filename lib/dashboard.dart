import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import 'controller.dart';
import 'models.dart';
import 'poe_dialog.dart';
import 'firmware_updates.dart';
import 'network_settings.dart';
import 'main.dart' show Brand, teal, muted, line;

const sections = [
  'Overview',
  'Ports',
  'Traffic',
  'PoE',
  'System',
  'Updates',
  'Network',
];
const sectionIcons = [
  Icons.space_dashboard_outlined,
  Icons.settings_ethernet,
  Icons.show_chart,
  Icons.bolt,
  Icons.dns_outlined,
  Icons.system_update_alt,
  Icons.lan_outlined,
];

class Dashboard extends StatefulWidget {
  final AirlinkController controller;
  const Dashboard({super.key, required this.controller});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Timer? _freshnessTimer;
  @override
  void initState() {
    super.initState();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  int section = 0;
  String selectedPort = 'all';
  AirlinkController get c => widget.controller;
  Snapshot? get s => c.snapshot;
  bool get stale =>
      s != null &&
      (s!.stale ||
          c.state == ConnectionState.error ||
          DateTime.now().difference(s!.updated).inSeconds >
              math.max(15, c.interval * 3));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    _header(wide),
                    if (c.busy) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(wide ? 30 : 18),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _statusBanner(),
                                const SizedBox(height: 24),
                                _title(),
                                const SizedBox(height: 24),
                                if (s == null)
                                  _empty()
                                else ...[
                                  if (section == 0) ...[
                                    _metrics(),
                                    const SizedBox(height: 24),
                                    _overview(),
                                  ],
                                  if (section == 1) ...[
                                    _portMap(),
                                    const SizedBox(height: 24),
                                    _portTable(),
                                  ],
                                  if (section == 2) ...[
                                    _traffic(),
                                    const SizedBox(height: 24),
                                    _portTable(),
                                  ],
                                  if (section == 3) _poe(),
                                  if (section == 4) _system(),
                                  if (section == 5)
                                    FirmwareUpdates(
                                      key: ValueKey(
                                        '${c.demo}/${c.profile?.url}/${c.profile?.deviceId}/${s!.device['model']}',
                                      ),
                                      snapshot: s!,
                                      demo: c.demo,
                                      stale: stale,
                                      onCheck: c.busy || c.controlBusy
                                          ? null
                                          : c.checkFirmware,
                                      checking: c.checkingUpdates,
                                      onlineResult: c.firmwareCheck,
                                      onlineError: c.firmwareCheckError,
                                    ),
                                  if (section == 6)
                                    NetworkSettings(
                                      key: ValueKey(
                                        'network/${c.demo}/${c.profile?.url}/${c.profile?.deviceId}/${s!.device['model']}',
                                      ),
                                      draftId: Uri.encodeComponent(
                                        '${c.demo}/${c.profile?.url}/${c.profile?.deviceId}/${s!.device['model']}',
                                      ),
                                      demo: c.demo,
                                    ),
                                  if (s!.warnings.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 20),
                                      child: _warnings(),
                                    ),
                                ],
                                const SizedBox(height: 26),
                                const Text(
                                  'MONITORING   •   PoE changes require separate permission and confirmation',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                labelTextStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 11),
                ),
                selectedIndex: section,
                onDestinationSelected: (v) => setState(() => section = v),
                destinations: List.generate(
                  sections.length,
                  (i) => NavigationDestination(
                    icon: Icon(sectionIcons[i]),
                    label: sections[i],
                  ),
                ),
              ),
      );
    },
  );

  Widget _sidebar() => Container(
    width: 224,
    decoration: const BoxDecoration(
      color: Color(0xFF0C1828),
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(),
        const SizedBox(height: 48),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text(
            'WORKSPACE',
            style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.8),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < sections.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: section == i
                  ? teal.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(
                  sectionIcons[i],
                  color: section == i ? teal : muted,
                  size: 21,
                ),
                title: Text(
                  sections[i],
                  style: TextStyle(
                    color: section == i ? teal : muted,
                    fontWeight: section == i
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                onTap: () => setState(() => section = i),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: teal, size: 22),
              SizedBox(height: 10),
              Text('Observe with confidence', style: TextStyle(fontSize: 12)),
              SizedBox(height: 5),
              Text(
                'Monitor freely. Review and confirm each PoE change.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'AIRLINK  /  1.0',
          style: TextStyle(color: muted, fontSize: 10, letterSpacing: 2),
        ),
      ],
    ),
  );

  Widget _header(bool wide) => Container(
    padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 16, vertical: 15),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!wide) ...[
          const Icon(Icons.hub_outlined, color: teal),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.demo ? 'Demo workspace' : c.profile!.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                c.demo
                    ? 'Simulated switch telemetry'
                    : 'Authenticated monitoring backend',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        if (wide) ...[
          const Icon(Icons.schedule, color: muted, size: 16),
          const SizedBox(width: 8),
          const Text('Poll', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(width: 10),
        ],
        DropdownButton<int>(
          value: c.interval,
          underline: const SizedBox(),
          style: const TextStyle(fontSize: 12, color: muted),
          items: [0, 5, 10, 30, 60]
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(v == 0 ? 'Manual' : '${v}s'),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) c.setInterval(v);
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refresh now',
          onPressed: c.busy ? null : c.refresh,
          icon: const Icon(Icons.refresh, size: 21),
        ),
        IconButton(
          tooltip: 'Disconnect',
          onPressed: c.disconnect,
          icon: const Icon(Icons.logout, size: 20),
        ),
      ],
    ),
  );

  Widget _statusBanner() {
    final color = stale || c.error != null
        ? Colors.orangeAccent
        : c.demo
        ? const Color(0xFFFFCA77)
        : teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            c.demo
                ? Icons.science_outlined
                : stale
                ? Icons.warning_amber_rounded
                : Icons.lock_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.demo
                  ? 'DEMO MODE — All readings and history are simulated. No live device is connected.'
                  : '${stale ? 'STALE READINGS — ' : ''}${c.error ?? 'LIVE MODE — Verified device identity over SSH. Read-only access.'}${s == null ? '' : ' Last successful update: ${s!.updated.toLocal()}'}',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 10,
    spacing: 24,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section == 0
                ? 'Network overview'
                : sections[section] == 'PoE'
                ? 'Power over Ethernet'
                : sections[section],
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s == null
                ? 'Waiting for a verified device snapshot'
                : '${s!.device['identity'] ?? 'Identity unavailable'}  /  ${s!.device['model']}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      if (s != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: stale ? Colors.orangeAccent : teal,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '${stale
                  ? 'Stale'
                  : c.demo
                  ? 'Simulated'
                  : s!.json['status']} · ${clockTime(s!.updated)}',
              style: TextStyle(
                color: stale ? Colors.orangeAccent : muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
    ],
  );

  Widget _empty() => SizedBox(
    height: 340,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.busy)
            const CircularProgressIndicator()
          else
            Icon(
              c.state == ConnectionState.unsupported
                  ? Icons.device_unknown
                  : Icons.cloud_off,
              size: 48,
              color: muted,
            ),
          const SizedBox(height: 20),
          Text(
            c.busy
                ? 'Collecting switch telemetry…'
                : c.state == ConnectionState.unsupported
                ? 'Device not supported or identity not verified'
                : 'Device disconnected',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 10),
          const Text(
            'Missing readings are never replaced with demo data.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: c.busy ? null : c.refresh,
            child: const Text('Retry connection'),
          ),
        ],
      ),
    ),
  );

  Widget _metrics() {
    final ports = s!.ports;
    final active = ports.where((p) => p['link'] == 'link-ok').length;
    final unknown = ports.where((p) => p['link'] == null).length;
    final powers = ports.where((p) => p['poe']['power_w'] is num).toList();
    final sumPower = powers.fold<double>(
      0,
      (sum, p) => sum + (p['poe']['power_w'] as num),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 950
            ? 4
            : constraints.maxWidth > 500
            ? 2
            : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children:
              [
                    _metric(
                      'ACTIVE LINKS',
                      '$active / ${ports.length}',
                      unknown > 0
                          ? '$unknown link states unavailable'
                          : 'Physical interfaces',
                      Icons.settings_ethernet,
                    ),
                    _metric(
                      'RECEIVE TRAFFIC',
                      reading(s!.total('rx_mbps'), 'Mbps'),
                      'Aggregate interface RX',
                      Icons.south_west,
                    ),
                    _metric(
                      'TRANSMIT TRAFFIC',
                      reading(s!.total('tx_mbps'), 'Mbps'),
                      'Aggregate interface TX',
                      Icons.north_east,
                    ),
                    _metric(
                      'REPORTED PoE DRAW',
                      powers.isEmpty
                          ? 'Unavailable'
                          : '${sumPower.toStringAsFixed(1)} W',
                      '${powers.length} ports reporting power',
                      Icons.bolt,
                    ),
                  ]
                  .map(
                    (w) => SizedBox(
                      width: (constraints.maxWidth - 16 * (cols - 1)) / cols,
                      child: w,
                    ),
                  )
                  .toList(),
        );
      },
    );
  }

  Widget _metric(String title, String value, String subtitle, IconData icon) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Icon(icon, color: teal, size: 19),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      );

  Widget _overview() => Column(
    children: [
      _portMap(),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, box) => box.maxWidth > 800
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: _traffic()),
                  const SizedBox(width: 24),
                  Expanded(flex: 4, child: _health()),
                ],
              )
            : Column(
                children: [_traffic(), const SizedBox(height: 24), _health()],
              ),
      ),
    ],
  );

  Widget _portMap() => _card(
    'Physical ports',
    'Discovered interface names · select a port for details',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: s!.ports.map((p) {
            final up = p['link'] == 'link-ok';
            final disabled = p['enabled'] == false;
            final color = disabled
                ? muted
                : p['link'] == null
                ? Colors.orangeAccent
                : up
                ? teal
                : const Color(0xFF64758A);
            return SizedBox(
              width: 74,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => _showPort(p),
                child: Column(
                  children: [
                    Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .07),
                        border: Border.all(color: color.withValues(alpha: .45)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              p['kind'] == 'Ethernet'
                                  ? Icons.settings_ethernet
                                  : Icons.memory,
                              color: color,
                              size: 30,
                            ),
                          ),
                          Positioned(
                            right: 7,
                            top: 6,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          if (p['poe']['status'] == 'powered-on')
                            const Positioned(
                              right: 5,
                              bottom: 4,
                              child: Icon(Icons.bolt, color: teal, size: 11),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      p['default_name'] as String,
                      style: const TextStyle(fontSize: 10, color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      disabled
                          ? 'Disabled'
                          : up
                          ? reading(p['speed_mbps'], 'M', 0)
                          : p['link'] == null
                          ? 'Unknown'
                          : 'No link',
                      style: TextStyle(fontSize: 9, color: color),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        const Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text('●  Link up', style: TextStyle(color: teal, fontSize: 11)),
            Text(
              '●  No link / disabled',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            Text('ϟ  PoE powered', style: TextStyle(color: teal, fontSize: 11)),
            Text(
              '●  Unknown',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _traffic() {
    final points = c.history[selectedPort] ?? [];
    return _card(
      'Traffic history',
      '${c.demo ? 'Simulated' : 'Observed'} · up to 120 samples · Mbps',
      Column(
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: s!.ports.any((p) => p['id'] == selectedPort)
                      ? selectedPort
                      : 'all',
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(color: muted, fontSize: 12),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All physical interfaces'),
                    ),
                    ...s!.ports.map(
                      (p) => DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text(p['name'] as String),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => selectedPort = v!),
                ),
              ),
              const SizedBox(width: 12),
              const Text('● RX', style: TextStyle(color: teal, fontSize: 11)),
              const SizedBox(width: 14),
              const Text(
                '● TX',
                style: TextStyle(color: Color(0xFF6AA6FF), fontSize: 11),
              ),
            ],
          ),
          SizedBox(
            height: 185,
            child: points.where((p) => p.rx != null || p.tx != null).length < 2
                ? const Center(
                    child: Text(
                      'Waiting for two rate samples\nUnavailable intervals appear as gaps.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  )
                : CustomPaint(
                    painter: TrafficPainter(points),
                    size: const Size(double.infinity, 185),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                points.isEmpty ? '—' : clockTime(points.first.time),
                style: const TextStyle(color: muted, fontSize: 10),
              ),
              Text(
                stale ? 'STALE · history paused' : 'Local time',
                style: TextStyle(
                  color: stale ? Colors.orangeAccent : muted,
                  fontSize: 10,
                ),
              ),
              Text(
                points.isEmpty ? '—' : clockTime(points.last.time),
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Interface totals can count switched traffic on both ingress and egress. They are not WAN throughput.',
            style: TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _health() {
    final sys = s!.system;
    final total = sys['total_memory_bytes'] as num?;
    final free = sys['free_memory_bytes'] as num?;
    final memory = total != null && free != null && total > 0
        ? (total - free) / total * 100
        : null;
    final temps = sys['temperatures'] as List? ?? [];
    return _card(
      'System health',
      'Reported by RouterOS',
      Column(
        children: [
          const SizedBox(height: 22),
          _healthBar('CPU load', sys['cpu_percent'] as num?, '%'),
          const SizedBox(height: 24),
          _healthBar('Memory used', memory, '%'),
          const SizedBox(height: 22),
          const Divider(),
          _detail(
            'Temperature',
            temps.isEmpty ? null : reading(temps.first['celsius'], '°C'),
          ),
          _detail('Uptime', sys['uptime']),
          _detail('RouterOS', sys['routeros_version']),
          _detail('Updated', _stamp(sys['observed_at'])),
        ],
      ),
    );
  }

  Widget _healthBar(String title, num? value, String unit) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: muted, fontSize: 12)),
          Text(reading(value, unit), style: const TextStyle(fontSize: 12)),
        ],
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: value == null ? 0 : (value / 100).clamp(0, 1),
          minHeight: 5,
          backgroundColor: line,
          color: teal,
        ),
      ),
    ],
  );

  Widget _portTable() => _card(
    'Interface telemetry',
    'Counters in bytes · rates in Mbps · scroll horizontally for more',
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(color: muted, fontSize: 11),
        dataTextStyle: const TextStyle(fontSize: 12),
        columnSpacing: 24,
        columns: [
          'Interface',
          'Link',
          'Enabled',
          'Speed Mbps',
          'Duplex',
          'RX Mbps',
          'TX Mbps',
          'RX bytes',
          'TX bytes',
          'Counters updated',
        ].map((v) => DataColumn(label: Text(v))).toList(),
        rows: s!.ports
            .map(
              (p) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      p['name'] as String,
                      style: const TextStyle(color: teal),
                    ),
                    onTap: () => _showPort(p),
                  ),
                  DataCell(Text(p['link'] ?? 'Unavailable')),
                  DataCell(Text(_bool(p['enabled'], 'Enabled', 'Disabled'))),
                  DataCell(Text(reading(p['speed_mbps'], '', 0))),
                  DataCell(Text(_bool(p['full_duplex'], 'Full', 'Half'))),
                  DataCell(Text(reading(p['rx_mbps']))),
                  DataCell(Text(reading(p['tx_mbps']))),
                  DataCell(Text(p['rx_bytes']?.toString() ?? 'Unavailable')),
                  DataCell(Text(p['tx_bytes']?.toString() ?? 'Unavailable')),
                  DataCell(Text(_stamp(p['counters_at']))),
                ],
              ),
            )
            .toList(),
      ),
    ),
  );

  Widget _poe() => _card(
    'PoE telemetry & control',
    'Only device-reported power values are shown. SFP interfaces do not supply PoE.',
    Column(
      children: [
        const Text(
          'On (Auto) enables detection. Off removes power. Controls require a fresh connection, '
          'an allowed port and a separate operator token. Every change needs confirmation.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        for (final p in s!.ports.where((p) => p['kind'] == 'Ethernet'))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(p['name'], style: const TextStyle(color: teal)),
                ),
                SizedBox(
                  width: 150,
                  child: Text(p['poe']['status'] ?? 'Unavailable'),
                ),
                SizedBox(
                  width: 95,
                  child: Text(reading(p['poe']['voltage_v'], 'V')),
                ),
                SizedBox(
                  width: 100,
                  child: Text(reading(p['poe']['current_a'], 'A', 3)),
                ),
                SizedBox(
                  width: 100,
                  child: Text(reading(p['poe']['power_w'], 'W')),
                ),
                Text(
                  _stamp(p['poe']['observed_at']),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                Text(
                  'Mode: ${p['poe']['configuration_mode'] ?? 'Unavailable'}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: Key('poe-on-${p['default_name']}'),
                      onPressed: stale || !c.canControlPoe(p)
                          ? null
                          : () => _changePoe(p, 'auto-on'),
                      child: const Text('On (Auto)'),
                    ),
                    OutlinedButton(
                      key: Key('poe-off-${p['default_name']}'),
                      onPressed: stale || !c.canControlPoe(p)
                          ? null
                          : () => _changePoe(p, 'off'),
                      child: const Text('Off'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          'Unavailable means the device did not provide a reading. No power values are inferred from voltage and current.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
  );

  Future<void> _changePoe(Json port, String mode) async {
    final epoch = c.beginPoe(port);
    try {
      final message = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            PoeDialog(controller: c, port: port, mode: mode, epoch: epoch),
      );
      if (mounted && message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      await c.endPoe(epoch);
    }
  }

  Widget _system() => _card(
    'Device & system',
    'Identity is verified against the backend profile before monitoring.',
    Column(
      children: [
        const SizedBox(height: 16),
        _detail('Model', s!.device['model']),
        _detail('Reported model', s!.device['reported_model']),
        _detail('Architecture', s!.device['architecture']),
        _detail('Device identity', s!.device['identity']),
        _detail(
          'Identity verification',
          c.demo ? 'Demo · not verified' : 'Verified model and physical ports',
        ),
        _detail('RouterOS version', s!.system['routeros_version']),
        _detail('Uptime', s!.system['uptime']),
        _detail('CPU load', reading(s!.system['cpu_percent'], '%')),
        _detail(
          'Free memory',
          reading(s!.system['free_memory_bytes'], 'bytes', 0),
        ),
        _detail(
          'Total memory',
          reading(s!.system['total_memory_bytes'], 'bytes', 0),
        ),
        if ((s!.system['temperatures'] as List).isEmpty)
          _detail('Temperature', null),
        for (final t in s!.system['temperatures'])
          _detail(t['name'], reading(t['celsius'], '°C')),
        _detail('System observed', _stamp(s!.system['observed_at'])),
        _detail('Health observed', _stamp(s!.system['health_at'])),
        _detail('Last successful collection', s!.updated.toLocal().toString()),
      ],
    ),
  );

  Widget _warnings() => ExpansionTile(
    title: Text(
      '${s!.warnings.length} unavailable telemetry sections',
      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
    ),
    children: s!.warnings
        .map(
          (w) => ListTile(
            dense: true,
            title: Text(w['section']),
            subtitle: Text(w['code']),
          ),
        )
        .toList(),
  );

  void _showPort(Json p) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(p['name']),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detail('Physical port', p['default_name']),
              _detail('Type', p['kind']),
              _detail('Link', p['link']),
              _detail(
                'Interface state',
                _bool(p['enabled'], 'Enabled', 'Disabled'),
              ),
              _detail('Negotiated speed', reading(p['speed_mbps'], 'Mbps', 0)),
              _detail('Duplex', _bool(p['full_duplex'], 'Full', 'Half')),
              _detail(
                'RX / TX',
                '${reading(p['rx_mbps'])} / ${reading(p['tx_mbps'])} Mbps',
              ),
              _detail('RX bytes', p['rx_bytes']),
              _detail('TX bytes', p['tx_bytes']),
              _detail(
                'Counter reset',
                p['counter_reset'] == true
                    ? 'Detected · rate baseline reset'
                    : 'Not detected',
              ),
              _detail('PoE status', p['poe']['status']),
              _detail('Voltage', reading(p['poe']['voltage_v'], 'V')),
              _detail('Current', reading(p['poe']['current_a'], 'A', 3)),
              _detail('Power', reading(p['poe']['power_w'], 'W')),
              _detail('Link observed', _stamp(p['observed_at'])),
              _detail('Counters observed', _stamp(p['counters_at'])),
              _detail('PoE observed', _stamp(p['poe']['observed_at'])),
              if (stale)
                const Text(
                  'STALE — these are last successful readings.',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  static String _bool(dynamic value, String yes, String no) => value == null
      ? 'Unavailable'
      : value == true
      ? yes
      : no;
  static String _stamp(dynamic value) => value is String
      ? DateTime.tryParse(value)?.toLocal().toString() ?? 'Unavailable'
      : 'Unavailable';
  Widget _detail(String key, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(key, style: const TextStyle(color: muted, fontSize: 12)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            value?.toString() ?? 'Unavailable',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
  Widget _card(String title, String subtitle, Widget child) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
          child,
        ],
      ),
    ),
  );
}

class TrafficPainter extends CustomPainter {
  final List<TrafficPoint> points;
  TrafficPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final maximum = math.max(
      1.0,
      points
              .expand((p) => [p.rx, p.tx])
              .whereType<double>()
              .fold<double>(0, math.max) *
          1.2,
    );
    const labelWidth = 35.0;
    final width = size.width - labelWidth;
    final height = size.height - 16;
    for (var i = 0; i < 5; i++) {
      final y = 8 + height * i / 4;
      canvas.drawLine(
        Offset(labelWidth, y),
        Offset(size.width, y),
        Paint()
          ..color = line
          ..strokeWidth = 1,
      );
      final label = TextPainter(
        text: TextSpan(
          text: (maximum * (1 - i / 4)).toStringAsFixed(0),
          style: const TextStyle(color: muted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - 5));
    }
    final start = points.first.time.millisecondsSinceEpoch;
    final duration = math.max(
      1,
      points.last.time.millisecondsSinceEpoch - start,
    );
    for (final rx in [true, false]) {
      final path = Path();
      var drawing = false;
      for (final p in points) {
        final value = rx ? p.rx : p.tx;
        if (value == null) {
          drawing = false;
          continue;
        }
        final x =
            labelWidth +
            width * (p.time.millisecondsSinceEpoch - start) / duration;
        final y = 8 + height * (1 - value / maximum);
        if (!drawing) {
          path.moveTo(x, y);
          drawing = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = (rx ? teal : const Color(0xFF6AA6FF))
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrafficPainter oldDelegate) => true;
}
