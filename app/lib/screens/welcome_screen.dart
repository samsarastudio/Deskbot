import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                FadeSlideIn(
                  child: Column(
                    children: [
                      Text(
                        'NOVA',
                        style: text.displayLarge?.copyWith(
                          color: NovaColors.accent,
                          shadows: [
                            Shadow(
                              color: NovaColors.accent.withValues(alpha: 0.35),
                              blurRadius: 28,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'your little desk companion',
                        style: text.bodyMedium?.copyWith(letterSpacing: 0.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                const FadeSlideIn(
                  delay: Duration(milliseconds: 90),
                  child: NovaMascot(mood: NovaMood.happy, size: 220, pulse: true),
                ),
                const SizedBox(height: 36),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: GlassPanel(
                    child: Text(
                      'Open once. NOVA finds your Deskbot by itself — no trip through Bluetooth Settings.',
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(height: 1.55),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 240),
                  child: NovaPrimaryButton(
                    label: 'Find my Deskbot',
                    onPressed: () => ref.read(bleControllerProvider.notifier).startScan(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
