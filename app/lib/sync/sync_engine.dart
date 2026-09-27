import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../ble/framing.dart';
import '../ble/uuids.dart';

class SyncEngine {
  SyncEngine({required this.sendJson, required this.ownerToken, required this.deviceId});

  final Future<void> Function(String json) sendJson;
  final String ownerToken;
  final String deviceId;

  int localRev = 1;
  bool authed = false;
  String? pendingNonce;
  int _authAttempts = 0;

  Future<void> sendHello() async {
    await sendJson(envelopeJson('HELLO', {
      'device_id': deviceId,
      'role': 'app',
      'app': DeskbotBle.appVersion,
      'protocol': DeskbotBle.protocolVersion,
    }));
  }

  Future<void> register({required String ownerToken, required String confirm}) async {
    await sendJson(envelopeJson('REGISTER', {
      'owner_token': ownerToken,
      'confirm': confirm,
    }));
  }

  /// HMAC-SHA256(owner_token, nonce) as lowercase hex — must match firmware hmac_hex().
  static String macHex(String ownerToken, String nonce) {
    final digest = Hmac(sha256, utf8.encode(ownerToken)).convert(utf8.encode(nonce));
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> respondAuth(String nonce) async {
    pendingNonce = nonce;
    await sendJson(envelopeJson('AUTH', {
      'op': 'response',
      'nonce': nonce,
      'mac': macHex(ownerToken, nonce),
    }));
  }

  Future<void> sendStateVersion() async {
    await sendJson(envelopeJson('STATE_VERSION', {'rev': localRev}));
  }

  /// Handle inbound JSON map. Returns a short UI hint if any.
  Future<String?> onMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String? ?? '';
    final body = (msg['body'] as Map?)?.cast<String, dynamic>() ?? {};
    switch (type) {
      case 'HELLO':
        // Deskbot hello — do NOT echo HELLO back. Echoing regenerates the auth
        // challenge nonce and makes our AUTH response fail with NACK.
        return null;
      case 'AUTH':
        if (body['op'] == 'challenge' && body['nonce'] is String) {
          _authAttempts++;
          await respondAuth(body['nonce'] as String);
        }
        return null;
      case 'ACK':
        authed = true;
        _authAttempts = 0;
        await sendStateVersion();
        return 'Linked';
      case 'NACK':
        authed = false;
        // One retry: desk may have rotated nonce if HELLO raced.
        if (_authAttempts < 2) {
          await sendHello();
          return 'Retrying auth…';
        }
        return 'Auth failed';
      case 'STATE_SNAPSHOT':
      case 'DELTA':
        final rev = body['rev'] ?? body['to'];
        if (rev is num) localRev = rev.toInt();
        authed = true;
        return 'Synced';
      case 'STATE_VERSION':
        if (authed) {
          await sendStateVersion();
        }
        return null;
      case 'UI_HINT':
        return body['code']?.toString();
      case 'CAPABILITIES':
        return null;
      default:
        return null;
    }
  }
}
