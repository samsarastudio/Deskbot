import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bleControllerProvider);
    final needCode = s.phase == BleLinkPhase.registering || s.phase == BleLinkPhase.found;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                NovaMascot(
                  mood: s.phase == BleLinkPhase.syncing ? NovaMood.thinking : NovaMood.focused,
                  size: 160,
                  pulse: true,
                ),
                const SizedBox(height: 22),
                Text(
                  s.status.isEmpty ? 'Linking your Deskbot…' : s.status,
                  style: text.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Look at Deskbot for the 4-digit code, then type it here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                if (needCode) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    enabled: s.status != 'Registering…' && s.status != 'Syncing…',
                    style: text.displaySmall?.copyWith(letterSpacing: 12),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '••••',
                    ),
                  ),
                  const SizedBox(height: 14),
                  NovaPrimaryButton(
                    label: s.status == 'Registering…' ? 'Setting up…' : 'Set up',
                    onPressed: (s.status == 'Registering…' || s.status == 'Syncing…')
                        ? null
                        : () {
                            ref.read(bleControllerProvider.notifier).confirmSetup(_code.text.trim());
                          },
                  ),
                ],
                const Spacer(),
                Text(
                  'The code only appears on the desk — not in this app.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
