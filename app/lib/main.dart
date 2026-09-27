import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble/ble_controller.dart';
import 'ble/nova_keepalive.dart';
import 'screens/home_gate.dart';
import 'theme/nova_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NovaKeepAlive.initCommunication();
  NovaKeepAlive.init();
  runApp(const ProviderScope(child: NovaApp()));
}

class NovaApp extends ConsumerStatefulWidget {
  const NovaApp({super.key});

  @override
  ConsumerState<NovaApp> createState() => _NovaAppState();
}

class _NovaAppState extends ConsumerState<NovaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ble = ref.read(bleControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        ble.onAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        ble.onAppBackgrounded();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOVA',
      debugShowCheckedModeBanner: false,
      theme: NovaTheme.dark(),
      home: const HomeGate(),
    );
  }
}
