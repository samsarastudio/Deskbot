import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/api_config.dart';
import '../cloud/auth_controller.dart';
import '../theme/nova_theme.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final TextEditingController _name;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _name = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).updateDisplayName(_name.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Account', style: text.titleLarge),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(user?.email ?? '', style: text.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save profile'),
          ),
          const SizedBox(height: 24),
          Text('Cloud', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(kDeskbotApiBase, style: text.bodySmall),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (!mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
            child: Text('Sign out', style: text.bodyMedium?.copyWith(color: NovaColors.bad)),
          ),
        ],
      ),
    );
  }
}
