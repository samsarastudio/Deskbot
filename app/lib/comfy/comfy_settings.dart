import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Comfy Cloud credentials live in the phone app only — never on the desk.
class ComfySettings {
  ComfySettings({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _keyApi = 'nova_comfy_api_key';

  Future<String?> loadApiKey() => _storage.read(key: _keyApi);

  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _keyApi);
      return;
    }
    await _storage.write(key: _keyApi, value: trimmed);
  }

  Future<bool> hasApiKey() async {
    final v = await loadApiKey();
    return v != null && v.isNotEmpty;
  }
}
