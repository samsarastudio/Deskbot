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
    final showCode = s.phase == BleLinkPhase.registering || s.confirmCode != null;
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
                const SizedBox(height: 16),
                if (s.confirmCode != null)
                  GlassPanel(
                    child: Column(
                      children: [
                        Text('Code on desk', style: text.bodyMedium),
                        const SizedBox(height: 8),
                        Text(
                          s.confirmCode!,
                          style: text.displaySmall?.copyWith(
                            color: NovaColors.gold,
                            letterSpacing: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (showCode) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    enabled: s.status != 'Registering…' && s.status != 'Syncing…',
                    style: text.displaySmall?.copyWith(letterSpacing: 12),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: s.confirmCode ?? '0000',
                    ),
                  ),
                  const SizedBox(height: 14),
                  NovaPrimaryButton(
                    label: s.status == 'Registering…' ? 'Setting up…' : 'Set up',
                    onPressed: (s.status == 'Registering…' || s.status == 'Syncing…')
                        ? null
                        : () {
                            final code = _code.text.trim().isEmpty
                                ? (s.confirmCode ?? '')
                                : _code.text.trim();
                            ref.read(bleControllerProvider.notifier).confirmSetup(code);
                          },
                  ),
                ],
                const Spacer(),
                Text(
                  'Stay in the app — permissions and linking happen here.',
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
