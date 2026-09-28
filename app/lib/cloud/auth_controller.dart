import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_store.dart';
import 'deskbot_cloud_api.dart';

enum AuthPhase { loading, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.phase = AuthPhase.loading,
    this.user,
    this.error,
  });

  final AuthPhase phase;
  final CloudUser? user;
  final String? error;

  AuthState copyWith({
    AuthPhase? phase,
    CloudUser? user,
    String? error,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authStoreProvider = Provider((_) => AuthStore());
final deskbotCloudApiProvider = Provider((_) => DeskbotCloudApi());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authStoreProvider),
    ref.watch(deskbotCloudApiProvider),
  );
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._store, this._api) : super(const AuthState()) {
    _bootstrap();
  }

  final AuthStore _store;
  final DeskbotCloudApi _api;
  String? _token;

  String? get token => _token;

  Future<void> _bootstrap() async {
    final token = await _store.loadToken();
    final cached = await _store.loadUser();
    if (token == null || token.isEmpty) {
      state = const AuthState(phase: AuthPhase.signedOut);
      return;
    }
    _token = token;
    try {
      final user = await _api.me(token);
      await _store.saveSession(token: token, user: user);
      state = AuthState(phase: AuthPhase.signedIn, user: user);
    } catch (_) {
      // Offline / expired — keep cached session if present so BLE still works.
      if (cached != null) {
        state = AuthState(phase: AuthPhase.signedIn, user: cached);
      } else {
        await _store.clear();
        _token = null;
        state = const AuthState(phase: AuthPhase.signedOut);
      }
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    state = state.copyWith(clearError: true);
    try {
      final result = await _api.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      _token = result.token;
      await _store.saveSession(token: result.token, user: result.user);
      state = AuthState(phase: AuthPhase.signedIn, user: result.user);
    } catch (e) {
      state = state.copyWith(phase: AuthPhase.signedOut, error: e.toString());
      rethrow;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(clearError: true);
    try {
      final result = await _api.login(email: email, password: password);
      _token = result.token;
      await _store.saveSession(token: result.token, user: result.user);
      state = AuthState(phase: AuthPhase.signedIn, user: result.user);
    } catch (e) {
      state = state.copyWith(phase: AuthPhase.signedOut, error: e.toString());
      rethrow;
    }
  }

  Future<void> updateDisplayName(String name) async {
    final token = _token;
    if (token == null) return;
    final user = await _api.updateMe(token, displayName: name);
    await _store.saveSession(token: token, user: user);
    state = AuthState(phase: AuthPhase.signedIn, user: user);
  }

  Future<void> logout() async {
    await _store.clear();
    _token = null;
    state = const AuthState(phase: AuthPhase.signedOut);
  }
}
