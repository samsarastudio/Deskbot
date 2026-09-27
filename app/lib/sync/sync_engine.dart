import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../ble/framing.dart';
import '../ble/uuids.dart';

class SyncEngine {
  SyncEngine({
    required this.sendJson,
    required this.ownerToken,
    required this.deviceId,
    this.localRev = 1,
    this.authFailures = 0,
  });

  final Future<void> Function(String json) sendJson;
  final String ownerToken;
  String deviceId;

  int localRev;
  bool authed = false;
  String? pendingNonce;
  /// Failed AUTH rounds (NACKs). Not reset on HELLO.
  int authFailures;
  bool _authInFlight = false;

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
    final mac = macHex(ownerToken, nonce);
    debugPrint('AUTH response nonce=${nonce.length}c token=${ownerToken.length}c');
    await sendJson(envelopeJson('AUTH', {
      'op': 'response',
      'nonce': nonce,
      'mac': mac,
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
        // Do NOT echo HELLO — that rotates the desk challenge nonce.
        final id = body['device_id']?.toString();
        if (id != null && id.isNotEmpty) deviceId = id;
        return null;
      case 'AUTH':
        if (body['op'] == 'challenge' && body['nonce'] is String) {
          if (_authInFlight) return null;
          _authInFlight = true;
          try {
            await respondAuth(body['nonce'] as String);
          } finally {
            _authInFlight = false;
          }
        }
        return null;
      case 'ACK':
        authed = true;
        authFailures = 0;
        await sendStateVersion();
        return 'Linked';
      case 'NACK':
        authed = false;
        authFailures++;
        // At most one automatic retry — never loop forever.
        if (authFailures <= 1) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await sendHello();
          return 'Retrying auth…';
        }
        return 'Auth failed';
      case 'STATE_SNAPSHOT':
      case 'DELTA':
        final rev = body['rev'] ?? body['to'];
        if (rev is num) localRev = rev.toInt();
        authed = true;
        authFailures = 0;
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
