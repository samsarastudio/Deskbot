import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RegisteredDeskbot {
  RegisteredDeskbot({
    required this.deviceId,
    required this.ownerToken,
    this.remoteId,
    this.name = 'NOVA',
    this.stateRev = 1,
  });

  final String deviceId;
  final String ownerToken;
  final String? remoteId;
  final String name;
  final int stateRev;

  Map<String, String> toMap() => {
        'device_id': deviceId,
        'owner_token': ownerToken,
        if (remoteId != null) 'remote_id': remoteId!,
        'name': name,
        'rev': '$stateRev',
      };

  static RegisteredDeskbot? fromMap(Map<String, String> m) {
    final id = m['device_id'];
    final token = m['owner_token'];
    if (id == null || token == null || token.isEmpty) return null;
    return RegisteredDeskbot(
      deviceId: id,
      ownerToken: token,
      remoteId: m['remote_id'],
      name: m['name'] ?? 'NOVA',
      stateRev: int.tryParse(m['rev'] ?? '1') ?? 1,
    );
  }
}

class DeskbotStore {
  DeskbotStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _prefix = 'nova_deskbot_';

  Future<RegisteredDeskbot?> load() async {
    final all = await _storage.readAll();
    final filtered = <String, String>{};
    for (final e in all.entries) {
      if (e.key.startsWith(_prefix)) {
        filtered[e.key.substring(_prefix.length)] = e.value;
      }
    }
    return RegisteredDeskbot.fromMap(filtered);
  }

  Future<void> save(RegisteredDeskbot bot) async {
    for (final e in bot.toMap().entries) {
      await _storage.write(key: '$_prefix${e.key}', value: e.value);
    }
  }

  Future<void> clear() async {
    final all = await _storage.readAll();
    for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
      await _storage.delete(key: key);
    }
  }
}
