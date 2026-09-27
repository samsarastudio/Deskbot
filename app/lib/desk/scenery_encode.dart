import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encode a photo into half-res RGB565 for Deskbot scenery (max 160×86).
Uint8List encodeSceneryRgb565(Uint8List bytes, {int maxW = 160, int maxH = 86}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode image');
  }
  final resized = img.copyResize(
    decoded,
    width: maxW,
    height: maxH,
    interpolation: img.Interpolation.average,
  );
  final out = Uint8List(resized.width * resized.height * 2);
  var i = 0;
  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final p = resized.getPixel(x, y);
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

({int w, int h}) scenerySize() => (w: 160, h: 86);
