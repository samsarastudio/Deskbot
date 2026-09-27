import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
  Completer<bool>? _displayAck;

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

  Future<void> sendDisplay(Map<String, dynamic> body) async {
    if (!authed) return;
    await sendJson(envelopeJson('DISPLAY', body));
  }

  Future<bool> sendDisplayWait(Map<String, dynamic> body) async {
    if (!authed) return false;
    _displayAck = Completer<bool>();
    try {
      await sendJson(envelopeJson('DISPLAY', body));
      return await _displayAck!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
    } finally {
      _displayAck = null;
    }
  }

  Future<void> pushNotify({
    required String title,
    required String body,
    String mood = 'curious',
    int ttlMs = 8000,
  }) {
    return sendDisplay({
      'op': 'notify',
      'title': title,
      'body': body,
      'mood': mood,
      'ttl_ms': ttlMs,
    });
  }

  Future<void> pushCalendar({String? title, String? when}) {
    if (title == null || title.isEmpty) {
      return sendDisplay({'op': 'calendar_clear'});
    }
    return sendDisplay({'op': 'calendar', 'title': title, 'when': when ?? ''});
  }

  Future<void> pushLayout({required bool eyes, required String clock}) {
    return sendDisplay({
      'op': 'layout',
      'eyes': eyes,
      'clock': clock,
    });
  }

  Future<void> pushTimeSync() {
    final now = DateTime.now();
    return sendDisplay({
      'op': 'time',
      'unix': now.millisecondsSinceEpoch ~/ 1000,
      'tz': 'EST5EDT,M3.2.0,M11.1.0',
    });
  }

  Future<void> uploadSceneryRgb565(Uint8List pixels, {required int w, required int h}) async {
    if (!authed) {
      throw StateError('Not linked — reconnect first');
    }
    final began = await sendDisplayWait({'op': 'scenery_begin', 'w': w, 'h': h, 'fmt': 'rgb565'});
    if (!began) {
      throw StateError('Deskbot rejected scenery (need more RAM?)');
    }

    // Stream chunks fast — ACK only begin + end (avoids multi-minute hangs).
    const chunk = 720;
    for (var off = 0; off < pixels.length; off += chunk) {
      final end = math.min(off + chunk, pixels.length);
      final slice = pixels.sublist(off, end);
      await sendDisplay({
        'op': 'scenery_chunk',
        'off': off,
        'data': base64Encode(slice),
      });
      await Future<void>.delayed(const Duration(milliseconds: 28));
    }

    final ended = await sendDisplayWait({'op': 'scenery_end'});
    if (!ended) {
      throw StateError('Scenery commit failed');
    }
  }

  Future<void> uploadAnimFrames(List<Uint8List> frames, {required int w, required int h, int fps = 8}) async {
    if (!authed) {
      throw StateError('Not linked — reconnect first');
    }
    if (frames.isEmpty) {
      throw StateError('No frames');
    }
    final began = await sendDisplayWait({
      'op': 'anim_begin',
      'w': w,
      'h': h,
      'frames': frames.length,
      'fps': fps,
    });
    if (!began) {
      throw StateError('Deskbot rejected animation');
    }
    const chunk = 720;
    for (var fi = 0; fi < frames.length; fi++) {
      final pixels = frames[fi];
      for (var off = 0; off < pixels.length; off += chunk) {
        final end = math.min(off + chunk, pixels.length);
        await sendDisplay({
          'op': 'anim_chunk',
          'frame': fi,
          'off': off,
          'data': base64Encode(pixels.sublist(off, end)),
        });
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
    }
    final ended = await sendDisplayWait({'op': 'anim_end'});
    if (!ended) {
      throw StateError('Animation commit failed');
    }
  }

  Future<void> clearScenery() => sendDisplay({'op': 'scenery_clear'});
  Future<void> clearAnim() => sendDisplay({'op': 'anim_clear'});

  void _completeDisplay(bool ok) {
    final c = _displayAck;
    if (c != null && !c.isCompleted) {
      c.complete(ok);
    }
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
        if (_displayAck != null) {
          _completeDisplay(true);
          return null;
        }
        final wasAuthed = authed;
        authed = true;
        authFailures = 0;
        if (!wasAuthed) {
          await sendStateVersion();
          return 'Linked';
        }
        return null;
      case 'NACK':
        if (_displayAck != null) {
          _completeDisplay(false);
          return null;
        }
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
