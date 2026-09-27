import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble/nova_keepalive.dart';
import 'screens/home_gate.dart';
import 'theme/nova_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NovaKeepAlive.initCommunication();
  NovaKeepAlive.init();
  runApp(const ProviderScope(child: NovaApp()));
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

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
