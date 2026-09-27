import 'dart:convert';
import 'dart:typed_data';

import 'uuids.dart';

class FragAssembler {
  int? _msgId;
  int _next = 0;
  final BytesBuilder _buf = BytesBuilder(copy: false);

  void reset() {
    _msgId = null;
    _next = 0;
    _buf.clear();
  }

  /// Returns complete payload bytes when a final fragment arrives.
  Uint8List? feed(Uint8List chunk) {
    if (chunk.length < 6 || chunk[0] != DeskbotBle.fragMagic) return null;
    final flags = chunk[1];
    final msgId = chunk[2] | (chunk[3] << 8);
    final index = chunk[4] | (chunk[5] << 8);
    if (_msgId == null || _msgId != msgId || index == 0) {
      _msgId = msgId;
      _next = 0;
      _buf.clear();
    }
    if (index != _next) {
      reset();
      return null;
    }
    _buf.add(chunk.sublist(6));
    _next++;
    if ((flags & DeskbotBle.fragFinal) != 0) {
      final out = _buf.toBytes();
      reset();
      return out;
    }
    return null;
  }
}

List<Uint8List> fragBuild(int msgId, List<int> data) {
  final out = <Uint8List>[];
  var off = 0;
  var index = 0;
  if (data.isEmpty) {
    out.add(_one(msgId, index, const [], finalFrag: true));
    return out;
  }
  while (off < data.length) {
    final end = (off + DeskbotBle.fragPayload).clamp(0, data.length);
    final slice = data.sublist(off, end);
    final more = end < data.length;
    out.add(_one(msgId, index, slice, finalFrag: !more));
    off = end;
    index++;
  }
  return out;
}

Uint8List _one(int msgId, int index, List<int> payload, {required bool finalFrag}) {
  final b = Uint8List(6 + payload.length);
  b[0] = DeskbotBle.fragMagic;
  b[1] = finalFrag ? DeskbotBle.fragFinal : DeskbotBle.fragMore;
  b[2] = msgId & 0xff;
  b[3] = (msgId >> 8) & 0xff;
  b[4] = index & 0xff;
  b[5] = (index >> 8) & 0xff;
  b.setRange(6, b.length, payload);
  return b;
}

Map<String, dynamic> envelope(String type, Map<String, dynamic> body, {String? id}) {
  return {
    'v': DeskbotBle.protocolVersion,
    'type': type,
    'id': id ?? 'a-${DateTime.now().millisecondsSinceEpoch}',
    'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'body': body,
  };
}

String envelopeJson(String type, Map<String, dynamic> body, {String? id}) =>
    jsonEncode(envelope(type, body, id: id));
