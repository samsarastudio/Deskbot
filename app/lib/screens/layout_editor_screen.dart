import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../ble/ble_controller.dart';
import '../desk/layout_prefs.dart';
import '../desk/scenery_encode.dart';
import '../theme/nova_theme.dart';

/// Desk LCD layout editor — place photos, toggle eyes, pick clock placement.
class LayoutEditorScreen extends ConsumerStatefulWidget {
  const LayoutEditorScreen({super.key});

  @override
  ConsumerState<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends ConsumerState<LayoutEditorScreen> {
  static const _lcdW = 320.0;
  static const _lcdH = 172.0;

  final _layers = <LayoutImageLayer>[];
  String? _selectedId;
  bool _eyes = true;
  String _clock = 'center';
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final saved = await LayoutPrefs.load();
    if (!mounted) return;
    setState(() {
      _eyes = saved.eyes;
      _clock = saved.clock;
      _layers
        ..clear()
        ..addAll(saved.layers);
      _selectedId = _layers.isEmpty ? null : _layers.last.id;
      _loading = false;
    });
  }

  Future<void> _persistLocal() async {
    await LayoutPrefs.save(eyes: _eyes, clock: _clock, layers: List.of(_layers));
  }

  LayoutImageLayer? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final l in _layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  Future<void> _addImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 90);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read that image')));
      }
      return;
    }
    final aspect = decoded.width / decoded.height;
    var nw = 0.55;
    var nh = nw * (_lcdW / _lcdH) / aspect;
    if (nh > 0.7) {
      nh = 0.55;
      nw = nh * aspect * (_lcdH / _lcdW);
    }
    final layer = LayoutImageLayer(
      id: const Uuid().v4(),
      bytes: bytes,
      decoded: decoded,
      nx: (1 - nw) / 2,
      ny: (1 - nh) / 2,
      nw: nw,
      nh: nh,
    );
    setState(() {
      _layers.add(layer);
      _selectedId = layer.id;
    });
    await _persistLocal();
  }

  void _removeSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _layers.removeWhere((l) => l.id == id);
      _selectedId = _layers.isEmpty ? null : _layers.last.id;
    });
    _persistLocal();
  }

  Future<void> _pushToDesk() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _persistLocal();
      final ble = ref.read(bleControllerProvider.notifier);
      await ble.pushLayout(eyes: _eyes, clock: _clock);
      if (_layers.isNotEmpty) {
        final pixels = bakeLayoutScenery(_layers);
        final size = scenerySize();
        await ble.uploadSceneryPixels(pixels, w: size.w, h: size.h);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_layers.isEmpty ? 'Layout saved on desk' : 'Layout + scenery saved on desk')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Push failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = _selected;

    if (_loading) {
      return const Scaffold(
        backgroundColor: NovaColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: NovaColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Desk layout', style: text.titleLarge),
        actions: [
          TextButton(
            onPressed: _busy ? null : _pushToDesk,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Push to desk'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: AspectRatio(
                aspectRatio: _lcdW / _lcdH,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      decoration: BoxDecoration(
                        color: NovaColors.lcd,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: NovaColors.line),
                        boxShadow: [
                          BoxShadow(color: NovaColors.accent.withValues(alpha: 0.12), blurRadius: 24),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          // Preview layers
                          for (final layer in _layers)
                            Positioned(
                              left: layer.nx * constraints.maxWidth,
                              top: layer.ny * constraints.maxHeight,
                              width: layer.nw * constraints.maxWidth,
                              height: layer.nh * constraints.maxHeight,
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedId = layer.id),
                                onPanUpdate: (d) {
                                  setState(() {
                                    layer.nx = (layer.nx + d.delta.dx / constraints.maxWidth).clamp(0.0, 1.0 - layer.nw);
                                    layer.ny = (layer.ny + d.delta.dy / constraints.maxHeight).clamp(0.0, 1.0 - layer.nh);
                                    _selectedId = layer.id;
                                  });
                                },
                                onPanEnd: (_) => _persistLocal(),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: layer.id == _selectedId ? NovaColors.accent : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Image.memory(layer.bytes, fit: BoxFit.fill),
                                ),
                              ),
                            ),
                          // Eyes ghost
                          if (_eyes) ...[
                            _eyeGhost(constraints, left: true),
                            _eyeGhost(constraints, left: false),
                          ],
                          // Clock ghost
                          if (_clock != 'off') _clockGhost(constraints),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text('Images', style: text.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _addImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                        label: const Text('Add image'),
                      ),
                      if (selected != null)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _removeSelected,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Remove'),
                        ),
                    ],
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 12),
                    Text('Size', style: text.bodyMedium),
                    Slider(
                      value: selected.nw.clamp(0.15, 1.0),
                      min: 0.15,
                      max: 1.0,
                      activeColor: NovaColors.accent,
                      onChanged: (v) {
                        setState(() {
                          final aspect = selected.nw / selected.nh;
                          selected.nw = v;
                          selected.nh = (v / aspect).clamp(0.12, 1.0);
                          selected.nx = selected.nx.clamp(0.0, 1.0 - selected.nw);
                          selected.ny = selected.ny.clamp(0.0, 1.0 - selected.nh);
                        });
                      },
                      onChangeEnd: (_) => _persistLocal(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('Face', style: text.titleMedium),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Show eyes', style: text.bodyLarge),
                    subtitle: Text('Off = photo / scenery desk mode', style: text.bodyMedium),
                    value: _eyes,
                    activeThumbColor: NovaColors.accent,
                    onChanged: (v) {
                      setState(() => _eyes = v);
                      _persistLocal();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Clock', style: text.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final opt in const [
                        ('off', 'Off'),
                        ('top', 'Top'),
                        ('center', 'Center'),
                        ('bottom', 'Bottom'),
                        ('left', 'Left'),
                        ('right', 'Right'),
                      ])
                        ChoiceChip(
                          label: Text(opt.$2),
                          selected: _clock == opt.$1,
                          onSelected: (_) {
                            setState(() => _clock = opt.$1);
                            _persistLocal();
                          },
                          selectedColor: NovaColors.accentSoft,
                          labelStyle: text.labelLarge?.copyWith(
                            color: _clock == opt.$1 ? NovaColors.accent : NovaColors.muted,
                          ),
                          backgroundColor: NovaColors.panelSolid,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Saved on this phone and on Deskbot after Push. Survives restarts.',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eyeGhost(BoxConstraints c, {required bool left}) {
    final cx = (left ? 50.0 : _lcdW - 50.0) / _lcdW * c.maxWidth;
    final cy = 90.0 / _lcdH * c.maxHeight;
    return Positioned(
      left: cx - 14,
      top: cy - 14,
      child: IgnorePointer(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: NovaColors.face.withValues(alpha: 0.55), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _clockGhost(BoxConstraints c) {
    double nx = 0.5, ny = 0.35;
    switch (_clock) {
      case 'top':
        ny = 0.08;
        break;
      case 'bottom':
        ny = 0.78;
        break;
      case 'left':
        nx = 0.18;
        ny = 0.5;
        break;
      case 'right':
        nx = 0.82;
        ny = 0.5;
        break;
      case 'center':
      default:
        ny = _eyes ? 0.32 : 0.45;
        break;
    }
    return Positioned(
      left: nx * c.maxWidth - 36,
      top: ny * c.maxHeight - 10,
      child: IgnorePointer(
        child: Text(
          '12:00',
          style: TextStyle(
            color: NovaColors.face.withValues(alpha: 0.7),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
