import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class RecoveryScreen extends ConsumerWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bleControllerProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                const NovaMascot(mood: NovaMood.worried, size: 150),
                const SizedBox(height: 20),
                Text('Let’s fix this', style: text.headlineMedium),
                const SizedBox(height: 12),
                GlassPanel(
                  child: Text(
                    s.error ?? s.status,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                ),
                const Spacer(),
                NovaPrimaryButton(
                  label: 'Try again',
                  onPressed: () => ref.read(bleControllerProvider.notifier).startScan(
                        autoConnectRegistered: s.registered != null,
                      ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Check Bluetooth'),
                ),
                TextButton(
                  onPressed: () => ref.read(bleControllerProvider.notifier).removeDeskbot(),
                  child: Text('Re-register / Remove', style: text.bodyMedium?.copyWith(color: NovaColors.bad)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
