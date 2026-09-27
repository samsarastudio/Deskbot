import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import 'home_screen.dart';
import 'recovery_screen.dart';
import 'search_screen.dart';
import 'setup_screen.dart';
import 'welcome_screen.dart';

class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bleControllerProvider);
    final child = switch (s.phase) {
      BleLinkPhase.idle => const WelcomeScreen(),
      BleLinkPhase.scanning || BleLinkPhase.found => const SearchScreen(),
      BleLinkPhase.connecting ||
      BleLinkPhase.registering ||
      BleLinkPhase.authenticating ||
      BleLinkPhase.syncing =>
        const SetupScreen(),
      BleLinkPhase.connected || BleLinkPhase.away || BleLinkPhase.reconnecting =>
        const HomeScreen(),
      BleLinkPhase.recovery => const RecoveryScreen(),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(s.phase),
        child: child,
      ),
    );
  }
}
