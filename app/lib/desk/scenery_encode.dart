import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Tiny pixel-art scenery for Deskbot (~1.1KB) — fits in one BLE DISPLAY message.
const int kSceneryW = 32;
const int kSceneryH = 18;

Uint8List encodeSceneryRgb565(
  Uint8List bytes, {
  int maxW = kSceneryW,
  int maxH = kSceneryH,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode image');
  }

  // Downsample with nearest-neighbor → chunky pixel look, then light palette.
  var small = img.copyResize(
    decoded,
    width: maxW,
    height: maxH,
    interpolation: img.Interpolation.nearest,
  );
  try {
    small = img.quantize(small, numberOfColors: 16);
  } catch (_) {
    // quantize optional — nearest resize alone is fine
  }

  final out = Uint8List(small.width * small.height * 2);
  var i = 0;
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      final p = small.getPixel(x, y);
      final r = p.r.toInt() & 0xff;
      final g = p.g.toInt() & 0xff;
      final b = p.b.toInt() & 0xff;
      final rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
      out[i++] = rgb565 & 0xff;
      out[i++] = (rgb565 >> 8) & 0xff;
    }
  }
  return out;
}

({int w, int h}) scenerySize() => (w: kSceneryW, h: kSceneryH);
