import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../sync/rssi_filter.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const SizedBox(height: 28),
                NovaMascot(mood: mood, size: 230, pulse: connected),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  child: Text(
                    connected ? 'Right here with you' : 'Still yours — waiting nearby',
                    key: ValueKey(connected),
                    style: text.titleLarge,
                  ),
                ),
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
