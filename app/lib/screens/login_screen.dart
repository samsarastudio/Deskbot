import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/auth_controller.dart';
import '../theme/nova_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/nova_mascot.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 8) {
      setState(() => _error = 'Use a valid email and password (8+ characters)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authControllerProvider.notifier);
      if (_signup) {
        await auth.register(
          email: email,
          password: password,
          displayName: _name.text.trim(),
        );
      } else {
        await auth.login(email: email, password: password);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            children: [
              const SizedBox(height: 24),
              Text(
                'NOVA',
                textAlign: TextAlign.center,
                style: text.displayMedium?.copyWith(color: NovaColors.accent),
              ),
              const SizedBox(height: 8),
              Text(
                _signup ? 'Create your account' : 'Sign in to continue',
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              const Center(child: NovaMascot(mood: NovaMood.curious, size: 140, pulse: true)),
              const SizedBox(height: 24),
              if (_signup) ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: text.bodyMedium?.copyWith(color: NovaColors.bad)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Please wait…' : (_signup ? 'Create account' : 'Sign in')),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _signup = !_signup;
                          _error = null;
                        }),
                child: Text(_signup ? 'Already have an account? Sign in' : 'New here? Create account'),
              ),
              const SizedBox(height: 12),
              Text(
                'Animations are generated on deskbot.inmomentservices.com — your Comfy key stays on the server.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
