import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';

/// Explicit per-action approval. The operator token only lives in this dialog.
class PoeDialog extends StatefulWidget {
  final AirlinkController controller;
  final Json port;
  final String mode;
  final int epoch;
  const PoeDialog({
    super.key,
    required this.controller,
    required this.port,
    required this.mode,
    required this.epoch,
  });

  @override
  State<PoeDialog> createState() => _PoeDialogState();
}

class _PoeDialogState extends State<PoeDialog> {
  final token = TextEditingController();
  Json? prepared;
  bool busy = false, acknowledged = false, attempted = false;
  String? error;

  @override
  void dispose() {
    token.clear();
    token.dispose();
    super.dispose();
  }

  Future<void> prepare() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.controller.preparePoe(
        widget.port,
        widget.mode,
        token.text,
        widget.epoch,
      );
      if (mounted) setState(() => prepared = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not prepare this action. Check the operator token, port allowlist, '
              'device connection and identity. No write was sent.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> commit() async {
    setState(() {
      busy = true;
      attempted = true;
      error = null;
    });
    try {
      final result = await widget.controller.commitPoe(
        prepared!,
        token.text,
        widget.epoch,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError ? e.message.toString() : 'Outcome unknown. Refresh and check the device before trying again.',
        );
      }
    } finally {
      token.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = widget.controller.demo;
    final on = widget.mode == 'auto-on';
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          '${demo ? 'DEMO · ' : ''}Turn PoE ${on ? 'on (Auto)' : 'off'}?',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.controller.profile?.label ?? widget.controller.snapshot?.device['identity']}\n'
                  '${widget.port['name']} · ${widget.port['default_name']}',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Changing PoE can power off a connected device and disconnect your '
                  'management connection. The management path is not detected.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'On (Auto) uses device detection; it does not guarantee power delivery. '
                  'Switching from forced-on to Auto can interrupt power. Forced-on is never enabled here.',
                ),
                if (demo) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Demo simulation only. No network command will be sent.',
                  ),
                ] else if (prepared == null) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('poe-operator-token'),
                    controller: token,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !busy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'PoE operator token',
                      helperText: 'Separate from monitoring. Used for this action only.',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
                if (prepared != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Verified setting: ${prepared!['previous_mode']} → ${prepared!['requested_mode']}',
                  ),
                  const Text('Confirmation expires after 60 seconds.'),
                  CheckboxListTile(
                    key: const Key('poe-acknowledgement'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: acknowledged,
                    onChanged: busy || attempted
                        ? null
                        : (v) => setState(() => acknowledged = v ?? false),
                    title: const Text(
                      'I confirm this port and accept possible power loss and disconnection.',
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(attempted ? 'Close & refresh' : 'Cancel'),
          ),
          if (prepared == null)
            FilledButton(
              onPressed: busy || (!demo && token.text.length < 32)
                  ? null
                  : prepare,
              child: const Text('Review current setting'),
            )
          else
            FilledButton(
              key: const Key('poe-confirm'),
              onPressed: busy || attempted || !acknowledged ? null : commit,
              child: Text(
                '${demo ? 'Simulate' : 'Confirm'} ${on ? 'On (Auto)' : 'Off'}',
              ),
            ),
        ],
      ),
    );
  }
}
