import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Half-LCD photo scenery (exact 2× upscale on desk). ~27KB RAM, chunked BLE.
const int kSceneryW = 160;
const int kSceneryH = 86;

/// Encode a gallery photo into dithered RGB565 — keeps photographic detail.
Uint8List encodeSceneryRgb565(
  Uint8List bytes, {
  int maxW = kSceneryW,
  int maxH = kSceneryH,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode image');
  }

  // Cover-crop to LCD aspect (320:172 ≈ 1.86), then high-quality downsample.
  final targetAspect = maxW / maxH;
  final srcAspect = decoded.width / decoded.height;
  img.Image cropped = decoded;
  if (srcAspect > targetAspect) {
    final newW = (decoded.height * targetAspect).round();
    final x0 = ((decoded.width - newW) / 2).round();
    cropped = img.copyCrop(decoded, x: x0, y: 0, width: newW, height: decoded.height);
  } else if (srcAspect < targetAspect) {
    final newH = (decoded.width / targetAspect).round();
    final y0 = ((decoded.height - newH) / 2).round();
    cropped = img.copyCrop(decoded, x: 0, y: y0, width: decoded.width, height: newH);
  }

  final small = img.copyResize(
    cropped,
    width: maxW,
    height: maxH,
    interpolation: img.Interpolation.average,
  );

  // Floyd–Steinberg dither into RGB565 so gradients still look like a photo.
  final errR = List<double>.filled(maxW * maxH, 0);
  final errG = List<double>.filled(maxW * maxH, 0);
  final errB = List<double>.filled(maxW * maxH, 0);
  final out = Uint8List(maxW * maxH * 2);
  var i = 0;

  double clamp8(double v) => v.clamp(0.0, 255.0);

  for (var y = 0; y < maxH; y++) {
    for (var x = 0; x < maxW; x++) {
      final idx = y * maxW + x;
      final p = small.getPixel(x, y);
      var r = clamp8(p.r.toDouble() + errR[idx]);
      var g = clamp8(p.g.toDouble() + errG[idx]);
      var b = clamp8(p.b.toDouble() + errB[idx]);

      final qR = (r / 255.0 * 31.0).round().clamp(0, 31);
      final qG = (g / 255.0 * 63.0).round().clamp(0, 63);
      final qB = (b / 255.0 * 31.0).round().clamp(0, 31);
      final r8 = (qR * 255 / 31).round();
      final g8 = (qG * 255 / 63).round();
      final b8 = (qB * 255 / 31).round();

      final rgb565 = (qR << 11) | (qG << 5) | qB;
      out[i++] = rgb565 & 0xff;
      out[i++] = (rgb565 >> 8) & 0xff;

      final dR = r - r8;
      final dG = g - g8;
      final dB = b - b8;

      void diffuse(int nx, int ny, double factor) {
        if (nx < 0 || nx >= maxW || ny < 0 || ny >= maxH) return;
        final j = ny * maxW + nx;
        errR[j] += dR * factor;
        errG[j] += dG * factor;
        errB[j] += dB * factor;
      }

      diffuse(x + 1, y, 7 / 16);
      diffuse(x - 1, y + 1, 3 / 16);
      diffuse(x, y + 1, 5 / 16);
      diffuse(x + 1, y + 1, 1 / 16);
    }
  }

  return out;
}

/// Dither an already-sized image (maxW×maxH) into RGB565.
Uint8List encodeImageToRgb565(img.Image small) {
  final maxW = small.width;
  final maxH = small.height;
  final errR = List<double>.filled(maxW * maxH, 0);
  final errG = List<double>.filled(maxW * maxH, 0);
  final errB = List<double>.filled(maxW * maxH, 0);
  final out = Uint8List(maxW * maxH * 2);
  var i = 0;
  double clamp8(double v) => v.clamp(0.0, 255.0);

  for (var y = 0; y < maxH; y++) {
    for (var x = 0; x < maxW; x++) {
      final idx = y * maxW + x;
      final p = small.getPixel(x, y);
      var r = clamp8(p.r.toDouble() + errR[idx]);
      var g = clamp8(p.g.toDouble() + errG[idx]);
      var b = clamp8(p.b.toDouble() + errB[idx]);

      final qR = (r / 255.0 * 31.0).round().clamp(0, 31);
      final qG = (g / 255.0 * 63.0).round().clamp(0, 63);
      final qB = (b / 255.0 * 31.0).round().clamp(0, 31);
      final r8 = (qR * 255 / 31).round();
      final g8 = (qG * 255 / 63).round();
      final b8 = (qB * 255 / 31).round();

      final rgb565 = (qR << 11) | (qG << 5) | qB;
      out[i++] = rgb565 & 0xff;
      out[i++] = (rgb565 >> 8) & 0xff;

      final dR = r - r8;
      final dG = g - g8;
      final dB = b - b8;

      void diffuse(int nx, int ny, double factor) {
        if (nx < 0 || nx >= maxW || ny < 0 || ny >= maxH) return;
        final j = ny * maxW + nx;
        errR[j] += dR * factor;
        errG[j] += dG * factor;
        errB[j] += dB * factor;
      }

      diffuse(x + 1, y, 7 / 16);
      diffuse(x - 1, y + 1, 3 / 16);
      diffuse(x, y + 1, 5 / 16);
      diffuse(x + 1, y + 1, 1 / 16);
    }
  }
  return out;
}

class LayoutImageLayer {
  LayoutImageLayer({
    required this.id,
    required this.bytes,
    required this.decoded,
    this.nx = 0.1,
    this.ny = 0.1,
    this.nw = 0.5,
    this.nh = 0.5,
  });

  final String id;
  final Uint8List bytes;
  final img.Image decoded;
  /// Normalized rect on the 320×172 desk canvas (0..1).
  double nx;
  double ny;
  double nw;
  double nh;
}

/// Composite layers onto half-LCD and encode RGB565 for upload.
Uint8List bakeLayoutScenery(
  List<LayoutImageLayer> layers, {
  int bgR = 7,
  int bgG = 16,
  int bgB = 24,
}) {
  final canvas = img.Image(width: kSceneryW, height: kSceneryH);
  img.fill(canvas, color: img.ColorRgba8(bgR, bgG, bgB, 255));

  for (final layer in layers) {
    final dx = (layer.nx * kSceneryW).round();
    final dy = (layer.ny * kSceneryH).round();
    final dw = (layer.nw * kSceneryW).round().clamp(1, kSceneryW);
    final dh = (layer.nh * kSceneryH).round().clamp(1, kSceneryH);
    final resized = img.copyResize(
      layer.decoded,
      width: dw,
      height: dh,
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  }
  return encodeImageToRgb565(canvas);
}

({int w, int h}) scenerySize() => (w: kSceneryW, h: kSceneryH);

/// Rough compressed size hint for UI (bytes of RGB565 payload).
int sceneryPayloadBytes() => kSceneryW * kSceneryH * 2;
