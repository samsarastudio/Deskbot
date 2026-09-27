import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ble/ble_controller.dart';
import '../sync/rssi_filter.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickScenery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    try {
      await ref.read(bleControllerProvider.notifier).uploadScenery(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scenery on Deskbot')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scenery failed: $e')),
        );
      }
    }
  }

  Future<void> _composeNotify() async {
    final title = TextEditingController(text: 'NOVA');
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          backgroundColor: NovaColors.panelSolid,
          title: Text('Show on Deskbot', style: text.titleLarge),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              TextField(controller: body, decoration: const InputDecoration(labelText: 'Message'), maxLines: 2),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        );
      },
    );
    if (ok == true && body.text.trim().isNotEmpty) {
      await ref.read(bleControllerProvider.notifier).pushNotify(title.text.trim(), body.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bleControllerProvider);
    final connected = s.phase == BleLinkPhase.connected;
    final text = Theme.of(context).textTheme;
    final mood = switch (s.phase) {
      BleLinkPhase.reconnecting => NovaMood.thinking,
      BleLinkPhase.away => NovaMood.sleepy,
      _ => s.proximity == ProximityBand.near ? NovaMood.happy : NovaMood.curious,
    };
    final pip = switch (s.phase) {
      BleLinkPhase.connected => 'Connected',
      BleLinkPhase.reconnecting => 'Reconnecting…',
      BleLinkPhase.away => 'Will reconnect',
      _ => s.status,
    };

    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    SoftStatusChip(label: pip, good: connected),
                    const Spacer(),
                    SoftStatusChip(
                      label: switch (s.proximity) {
                        ProximityBand.near => 'Near',
                        ProximityBand.weak => 'Weak signal',
                        ProximityBand.away => 'Away',
                      },
                      good: s.proximity != ProximityBand.away,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'NOVA',
                  style: text.displayMedium?.copyWith(
                    color: NovaColors.accent,
                    shadows: [
                      Shadow(color: NovaColors.accent.withValues(alpha: 0.3), blurRadius: 24),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(s.registered?.deviceId ?? 'Deskbot', style: text.bodyMedium),
                const SizedBox(height: 20),
                NovaMascot(mood: mood, size: 180, pulse: connected),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  child: Text(
                    connected ? 'Right here with you' : 'Still yours — waiting nearby',
                    key: ValueKey(connected),
                    style: text.titleLarge,
                  ),
                ),
                if (connected) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : () => _run(_composeNotify),
                        child: const Text('Notify desk'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _run(_pickScenery),
                        child: const Text('Upload scenery'),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => ref.read(bleControllerProvider.notifier).refreshCalendar()),
                        child: const Text('Calendar'),
                      ),
                      if (Platform.isAndroid)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => ref.read(bleControllerProvider.notifier).openNotificationAccess()),
                          child: const Text('Phone alerts'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => ref.read(bleControllerProvider.notifier).clearScenery()),
                        child: const Text('Clear scenery'),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                OutlinedButton(
                  onPressed: () => ref.read(bleControllerProvider.notifier).startScan(autoConnectRegistered: true),
                  child: const Text('Refresh connection'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: NovaColors.panelSolid,
                        title: Text('Remove Deskbot?', style: text.titleLarge),
                        content: Text(
                          'Clears phone registration. Deskbot may need re-setup.',
                          style: text.bodyMedium,
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Remove', style: TextStyle(color: NovaColors.bad)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(bleControllerProvider.notifier).removeDeskbot();
                    }
                  },
                  child: Text('Remove Deskbot', style: text.bodyMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
