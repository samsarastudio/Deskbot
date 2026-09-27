import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_controller.dart';
import '../comfy/comfy_ltx_service.dart';
import '../comfy/comfy_settings.dart';
import '../comfy/ltx_prompt_builder.dart';
import '../theme/nova_theme.dart';

final comfySettingsProvider = Provider((_) => ComfySettings());
final comfyLtxServiceProvider = Provider((_) => ComfyLtxService());

/// App-side LTX message: pick style pieces → auto prompt → Comfy → desk.
class MessageAnimScreen extends ConsumerStatefulWidget {
  const MessageAnimScreen({super.key});

  @override
  ConsumerState<MessageAnimScreen> createState() => _MessageAnimScreenState();
}

class _MessageAnimScreenState extends ConsumerState<MessageAnimScreen> {
  final _apiKey = TextEditingController();
  final _styleNote = TextEditingController(text: 'manga style');
  final _promptOverride = TextEditingController();

  LtxPromptSelection _sel = const LtxPromptSelection();
  bool _busy = false;
  bool _editPrompt = false;
  String _stage = '';
  int _duration = 4;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final key = await ref.read(comfySettingsProvider).loadApiKey();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      if (key != null) _apiKey.text = key;
      _sel = LtxPromptSelection.fromPrefs({
        'character': prefs.getString('ltx_character'),
        'motion': prefs.getString('ltx_motion'),
        'emotion': prefs.getString('ltx_emotion'),
        'power': prefs.getString('ltx_power'),
        'style': prefs.getString('ltx_style'),
      });
      _styleNote.text = _sel.styleNote;
      _duration = prefs.getInt('ltx_duration') ?? 4;
      _promptOverride.text = _sel.build();
    });
  }

  Future<void> _persistSel() async {
    final prefs = await SharedPreferences.getInstance();
    final m = _sel.toPrefs();
    await prefs.setString('ltx_character', m['character']!);
    await prefs.setString('ltx_motion', m['motion']!);
    await prefs.setString('ltx_emotion', m['emotion']!);
    await prefs.setString('ltx_power', m['power']!);
    await prefs.setString('ltx_style', m['style']!);
    await prefs.setInt('ltx_duration', _duration);
  }

  void _updateSel(LtxPromptSelection next) {
    setState(() {
      _sel = next;
      if (!_editPrompt) {
        _promptOverride.text = next.build();
      }
    });
    _persistSel();
  }

  String get _activePrompt {
    if (_editPrompt) {
      final t = _promptOverride.text.trim();
      if (t.isNotEmpty) return t;
    }
    return _sel.copyWith(styleNote: _styleNote.text).build();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _styleNote.dispose();
    _promptOverride.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await ref.read(comfySettingsProvider).saveApiKey(_apiKey.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comfy key saved on phone')),
    );
  }

  Future<void> _generateAndPush() async {
    final key = _apiKey.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste your Comfy Cloud API key first')),
      );
      return;
    }
    final prompt = _activePrompt;
    if (prompt.isEmpty) return;

    final ble = ref.read(bleControllerProvider.notifier);
    final phase = ref.read(bleControllerProvider).phase;
    if (phase != BleLinkPhase.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to Deskbot first')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _stage = 'Starting…';
    });

    try {
      await ref.read(comfySettingsProvider).saveApiKey(key);
      await _persistSel();
      final frames = await ref.read(comfyLtxServiceProvider).generateDeskFrames(
            apiKey: key,
            prompt: prompt,
            durationSec: _duration,
            onProgress: (s) {
              if (mounted) setState(() => _stage = s);
            },
          );

      setState(() => _stage = 'Sending to Deskbot…');
      await ble.pushLayout(eyes: false, clock: 'off');
      await ble.uploadAnimFrames(frames, fps: 8);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message playing on Deskbot')),
      );
      setState(() => _stage = 'Done');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generate failed: $e')),
      );
      setState(() => _stage = '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _choiceChips({
    required List<LtxChoice> choices,
    required String selectedId,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in choices)
          ChoiceChip(
            label: Text(c.label),
            selected: c.id == selectedId,
            onSelected: _busy ? null : (_) => onSelect(c.id),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final live = _sel.copyWith(styleNote: _styleNote.text);

    return Scaffold(
      appBar: AppBar(
        title: Text('LTX message', style: text.titleLarge),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              'Pick character, motion, emotion, and power — the app writes the Comfy prompt.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Comfy Cloud API key',
                hintText: 'comfyui-…',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _busy ? null : _saveKey, child: const Text('Save key')),
            ),
            _sectionTitle('Character'),
            _choiceChips(
              choices: ltxCharacters,
              selectedId: _sel.characterId,
              onSelect: (id) => _updateSel(_sel.copyWith(characterId: id, styleNote: _styleNote.text)),
            ),
            _sectionTitle('Motion'),
            _choiceChips(
              choices: ltxMotions,
              selectedId: _sel.motionId,
              onSelect: (id) => _updateSel(_sel.copyWith(motionId: id, styleNote: _styleNote.text)),
            ),
            _sectionTitle('Emotion'),
            _choiceChips(
              choices: ltxEmotions,
              selectedId: _sel.emotionId,
              onSelect: (id) => _updateSel(_sel.copyWith(emotionId: id, styleNote: _styleNote.text)),
            ),
            _sectionTitle('Power'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in ltxPowers)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p.id == _sel.powerId,
                    onSelected: _busy
                        ? null
                        : (_) => _updateSel(_sel.copyWith(powerId: p.id, styleNote: _styleNote.text)),
                  ),
              ],
            ),
            _sectionTitle('Art style'),
            TextField(
              controller: _styleNote,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: 'manga style, watercolor, neon cyberpunk…',
              ),
              onChanged: (v) {
                _updateSel(_sel.copyWith(styleNote: v));
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Auto prompt', style: text.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _editPrompt = !_editPrompt;
                            if (!_editPrompt) {
                              _promptOverride.text = live.build();
                            }
                          });
                        },
                  child: Text(_editPrompt ? 'Use auto' : 'Edit'),
                ),
              ],
            ),
            if (_editPrompt)
              TextField(
                controller: _promptOverride,
                maxLines: 5,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Custom prompt',
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NovaColors.panelSolid.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NovaColors.accent.withValues(alpha: 0.25)),
                ),
                child: Text(live.build(), style: text.bodySmall),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Duration', style: text.bodyMedium),
                Expanded(
                  child: Slider(
                    value: _duration.toDouble(),
                    min: 3,
                    max: 6,
                    divisions: 3,
                    label: '${_duration}s',
                    onChanged: _busy
                        ? null
                        : (v) {
                            setState(() => _duration = v.round());
                            _persistSel();
                          },
                  ),
                ),
                Text('${_duration}s', style: text.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _generateAndPush,
              child: Text(_busy ? 'Working…' : 'Generate & play on desk'),
            ),
            if (_stage.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_stage, style: text.bodyMedium?.copyWith(color: NovaColors.accent)),
            ],
          ],
        ),
      ),
    );
  }
}
