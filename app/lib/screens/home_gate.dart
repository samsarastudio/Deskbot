import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../cloud/auth_controller.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'recovery_screen.dart';
import 'search_screen.dart';
import 'setup_screen.dart';
import 'welcome_screen.dart';

/// Cloud account first, then Deskbot BLE pairing / home.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.phase == AuthPhase.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.phase == AuthPhase.signedOut) {
      return const LoginScreen();
    }

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
        key: ValueKey('auth-${auth.phase}-ble-${s.phase}'),
        child: child,
      ),
    );
  }
}
