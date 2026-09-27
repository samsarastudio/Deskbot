import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scenery_encode.dart';

/// Persists desk layout editor state across app restarts.
class LayoutPrefs {
  LayoutPrefs._();

  static const _kEyes = 'nova_layout_eyes';
  static const _kClock = 'nova_layout_clock';
  static const _kMeta = 'nova_layout_meta';

  static Future<({bool eyes, String clock, List<LayoutImageLayer> layers})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final eyes = prefs.getBool(_kEyes) ?? true;
    final clock = prefs.getString(_kClock) ?? 'center';
    final layers = <LayoutImageLayer>[];

    final metaRaw = prefs.getString(_kMeta);
    if (metaRaw != null && metaRaw.isNotEmpty) {
      final dir = await _layoutDir();
      final list = jsonDecode(metaRaw) as List<dynamic>;
      for (final item in list) {
        final m = (item as Map).cast<String, dynamic>();
        final id = m['id']?.toString();
        if (id == null) continue;
        final file = File(p.join(dir.path, '$id.jpg'));
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        layers.add(LayoutImageLayer(
          id: id,
          bytes: bytes,
          decoded: decoded,
          nx: (m['nx'] as num?)?.toDouble() ?? 0.1,
          ny: (m['ny'] as num?)?.toDouble() ?? 0.1,
          nw: (m['nw'] as num?)?.toDouble() ?? 0.5,
          nh: (m['nh'] as num?)?.toDouble() ?? 0.5,
        ));
      }
    }
    return (eyes: eyes, clock: clock, layers: layers);
  }

  static Future<void> save({
    required bool eyes,
    required String clock,
    required List<LayoutImageLayer> layers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEyes, eyes);
    await prefs.setString(_kClock, clock);

    final dir = await _layoutDir();
    // Remove stale image files.
    final keep = layers.map((l) => l.id).toSet();
    if (await dir.exists()) {
      for (final f in dir.listSync().whereType<File>()) {
        final base = p.basenameWithoutExtension(f.path);
        if (!keep.contains(base)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }

    final meta = <Map<String, dynamic>>[];
    for (final layer in layers) {
      final file = File(p.join(dir.path, '${layer.id}.jpg'));
      // Re-encode moderately sized JPEG for persistence.
      final encoded = img.encodeJpg(layer.decoded, quality: 85);
      await file.writeAsBytes(encoded, flush: true);
      meta.add({
        'id': layer.id,
        'nx': layer.nx,
        'ny': layer.ny,
        'nw': layer.nw,
        'nh': layer.nh,
      });
    }
    await prefs.setString(_kMeta, jsonEncode(meta));
  }

  static Future<Directory> _layoutDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'nova_layout'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
