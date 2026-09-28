import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scenery_encode.dart';

const int kAnimW = 128;
const int kAnimH = 68;
const int kAnimMaxFrames = 12;
const int kAnimFps = 10;

class MangaLibraryItem {
  const MangaLibraryItem({
    required this.id,
    required this.title,
    required this.assetGif,
    required this.assetPreview,
  });

  final String id;
  final String title;
  final String assetGif;
  final String assetPreview;
}

const mangaLibrary = <MangaLibraryItem>[
  MangaLibraryItem(
    id: 'ltx_kamehameha',
    title: 'LTX Live',
    assetGif: 'assets/manga/ltx_kamehameha.gif',
    assetPreview: 'assets/manga/manga_01_rooftop.png',
  ),
  MangaLibraryItem(
    id: 'rooftop_rain',
    title: 'Rooftop Rain',
    assetGif: 'assets/manga/rooftop_rain.gif',
    assetPreview: 'assets/manga/manga_01_rooftop.png',
  ),
  MangaLibraryItem(
    id: 'sakura_path',
    title: 'Sakura Path',
    assetGif: 'assets/manga/sakura_path.gif',
    assetPreview: 'assets/manga/manga_02_sakura.png',
  ),
  MangaLibraryItem(
    id: 'night_train',
    title: 'Night Train',
    assetGif: 'assets/manga/night_train.gif',
    assetPreview: 'assets/manga/manga_03_train.png',
  ),
  MangaLibraryItem(
    id: 'lantern_forest',
    title: 'Lantern Forest',
    assetGif: 'assets/manga/lantern_forest.gif',
    assetPreview: 'assets/manga/manga_04_forest.png',
  ),
  MangaLibraryItem(
    id: 'rainy_cafe',
    title: 'Rainy Cafe',
    assetGif: 'assets/manga/rainy_cafe.gif',
    assetPreview: 'assets/manga/manga_05_cafe.png',
  ),
];

/// Decode a GIF/WebP animation into dithered RGB565 frames for Deskbot.
List<Uint8List> encodeGifToAnimFrames(Uint8List bytes, {int maxFrames = kAnimMaxFrames}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode animation');
  }

  final frames = decoded.frames.isNotEmpty ? decoded.frames : <img.Image>[decoded];
  final step = frames.length <= maxFrames ? 1 : (frames.length / maxFrames).ceil();
  final picked = <img.Image>[];
  for (var i = 0; i < frames.length && picked.length < maxFrames; i += step) {
    picked.add(frames[i]);
  }
  if (picked.isEmpty) {
    picked.add(frames.first);
  }

  return [
    for (final f in picked)
      encodeImageToRgb565(
        img.copyResize(f, width: kAnimW, height: kAnimH, interpolation: img.Interpolation.average),
      ),
  ];
}
