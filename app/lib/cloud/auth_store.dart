import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudUser {
  const CloudUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  final int id;
  final String email;
  final String displayName;

  factory CloudUser.fromJson(Map<String, dynamic> j) => CloudUser(
        id: (j['user_id'] ?? j['id']) as int,
        email: j['email'] as String,
        displayName: (j['display_name'] ?? '') as String,
      );
}

class AuthStore {
  AuthStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'nova_cloud_jwt';
  static const _userIdKey = 'nova_cloud_user_id';
  static const _emailKey = 'nova_cloud_email';
  static const _nameKey = 'nova_cloud_display_name';

  Future<String?> loadToken() => _storage.read(key: _tokenKey);

  Future<CloudUser?> loadUser() async {
    final idRaw = await _storage.read(key: _userIdKey);
    final email = await _storage.read(key: _emailKey);
    final name = await _storage.read(key: _nameKey);
    final id = int.tryParse(idRaw ?? '');
    if (id == null || email == null || email.isEmpty) return null;
    return CloudUser(id: id, email: email, displayName: name ?? '');
  }

  Future<void> saveSession({
    required String token,
    required CloudUser user,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: '${user.id}');
    await _storage.write(key: _emailKey, value: user.email);
    await _storage.write(key: _nameKey, value: user.displayName);
  }

  Future<void> updateDisplayName(String name) async {
    await _storage.write(key: _nameKey, value: name);
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _nameKey);
  }
}
