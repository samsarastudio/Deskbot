import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bleControllerProvider);
    final found = s.devices.isNotEmpty;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () async {
                      await ref.read(bleControllerProvider.notifier).stopScan();
                      await ref.read(bleControllerProvider.notifier).removeDeskbot();
                    },
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: NovaColors.muted),
                  ),
                ),
                const Spacer(),
                NovaMascot(
                  mood: found ? NovaMood.curious : NovaMood.thinking,
                  size: 170,
                  pulse: true,
                ),
                const SizedBox(height: 22),
                Text(
                  found ? 'Deskbot found' : 'Looking for your Deskbot…',
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  found
                      ? 'Confirm it’s yours, then set up.'
                      : 'Scanning only for NOVA’s BLE service — not a raw device dump.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 28),
                if (found)
                  ...s.devices.take(3).map((d) {
                    final name = d.advertisementData.advName.isNotEmpty
                        ? d.advertisementData.advName
                        : 'NOVA';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassPanel(
                        onTap: () => ref.read(bleControllerProvider.notifier).connect(d.device),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: text.titleMedium),
                                  const SizedBox(height: 4),
                                  Text('Signal ${d.rssi} dBm', style: text.bodyMedium),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded, color: NovaColors.accent),
                          ],
                        ),
                      ),
                    );
                  }),
                const Spacer(),
                if (!found)
                  TextButton(
                    onPressed: () => ref.read(bleControllerProvider.notifier).startScan(),
                    child: Text('Keep looking', style: text.titleMedium?.copyWith(color: NovaColors.accent)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
