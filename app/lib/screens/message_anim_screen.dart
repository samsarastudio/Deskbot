import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_controller.dart';
import '../cloud/auth_controller.dart';
import '../cloud/deskbot_cloud_api.dart';
import '../comfy/ltx_prompt_builder.dart';
import '../desk/manga_library.dart';
import '../theme/nova_theme.dart';

/// Full LTX generator: create (3/day) + gallery of past generations.
class MessageAnimScreen extends ConsumerStatefulWidget {
  const MessageAnimScreen({super.key});

  @override
  ConsumerState<MessageAnimScreen> createState() => _MessageAnimScreenState();
}

class _MessageAnimScreenState extends ConsumerState<MessageAnimScreen> with SingleTickerProviderStateMixin {
  final _styleNote = TextEditingController(text: 'manga style');
  final _promptOverride = TextEditingController();
  final _title = TextEditingController();
  final _characterCustom = TextEditingController();
  final _motionCustom = TextEditingController();
  final _emotionCustom = TextEditingController();
  final _powerCustom = TextEditingController();

  late final TabController _tabs;
  LtxPromptSelection _sel = const LtxPromptSelection();
  LtxQuota? _quota;
  List<LtxJobSummary> _gallery = const [];
  final Map<String, Uint8List> _previews = {};

  bool _busy = false;
  bool _editPrompt = false;
  bool _loadingGallery = false;
  String _stage = '';
  int _duration = 4;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_tabs.indexIsChanging) {
        _refreshGallery();
      }
    });
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sel = LtxPromptSelection.fromPrefs({
        'character': prefs.getString('ltx_character'),
        'motion': prefs.getString('ltx_motion'),
        'emotion': prefs.getString('ltx_emotion'),
        'power': prefs.getString('ltx_power'),
        'style': prefs.getString('ltx_style'),
        'character_custom': prefs.getString('ltx_character_custom'),
        'motion_custom': prefs.getString('ltx_motion_custom'),
        'emotion_custom': prefs.getString('ltx_emotion_custom'),
        'power_custom': prefs.getString('ltx_power_custom'),
      });
      _styleNote.text = _sel.styleNote;
      _characterCustom.text = _sel.characterCustom;
      _motionCustom.text = _sel.motionCustom;
      _emotionCustom.text = _sel.emotionCustom;
      _powerCustom.text = _sel.powerCustom;
      _duration = prefs.getInt('ltx_duration') ?? 4;
      _promptOverride.text = _sel.build();
      _title.text = _sel.motionId == 'custom' && _sel.motionCustom.trim().isNotEmpty
          ? _sel.motionCustom.trim().split(',').first
          : _sel.motion.label;
    });
    await Future.wait([_refreshQuota(), _refreshGallery()]);
  }

  Future<void> _persistSel() async {
    final prefs = await SharedPreferences.getInstance();
    final m = _sel.toPrefs();
    await prefs.setString('ltx_character', m['character']!);
    await prefs.setString('ltx_motion', m['motion']!);
    await prefs.setString('ltx_emotion', m['emotion']!);
    await prefs.setString('ltx_power', m['power']!);
    await prefs.setString('ltx_style', m['style']!);
    await prefs.setString('ltx_character_custom', m['character_custom']!);
    await prefs.setString('ltx_motion_custom', m['motion_custom']!);
    await prefs.setString('ltx_emotion_custom', m['emotion_custom']!);
    await prefs.setString('ltx_power_custom', m['power_custom']!);
    await prefs.setInt('ltx_duration', _duration);
  }

  String? get _token => ref.read(authControllerProvider.notifier).token;

  Future<void> _refreshQuota() async {
    final token = _token;
    if (token == null) return;
    try {
      final q = await ref.read(deskbotCloudApiProvider).getLtxQuota(token);
      if (mounted) setState(() => _quota = q);
    } catch (_) {}
  }

  Future<void> _refreshGallery() async {
    final token = _token;
    if (token == null) return;
    setState(() => _loadingGallery = true);
    try {
      final api = ref.read(deskbotCloudApiProvider);
      final jobs = await api.listLtxJobs(token, limit: 40);
      if (!mounted) return;
      setState(() => _gallery = jobs);
      for (final job in jobs.where((j) => j.status == 'succeeded' && !_previews.containsKey(j.id))) {
        try {
          final bytes = await api.fetchPreviewBytes(token, job.id);
          if (mounted) setState(() => _previews[job.id] = bytes);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingGallery = false);
    }
  }

  LtxPromptSelection _selWithCustoms() {
    return _sel.copyWith(
      styleNote: _styleNote.text,
      characterCustom: _characterCustom.text,
      motionCustom: _motionCustom.text,
      emotionCustom: _emotionCustom.text,
      powerCustom: _powerCustom.text,
    );
  }

  void _updateSel(LtxPromptSelection next) {
    setState(() {
      _sel = next;
      if (!_editPrompt) {
        _promptOverride.text = next.build();
      }
      final motionLabel = next.motionId == 'custom' && next.motionCustom.trim().isNotEmpty
          ? next.motionCustom.trim().split(',').first
          : next.motion.label;
      if (_title.text.trim().isEmpty ||
          _title.text == _sel.motion.label ||
          _title.text == motionLabel) {
        _title.text = motionLabel;
      }
    });
    _persistSel();
  }

  String get _activePrompt {
    if (_editPrompt) {
      final t = _promptOverride.text.trim();
      if (t.isNotEmpty) return t;
    }
    return _selWithCustoms().build();
  }

  Future<void> _pushFramesToDesk(List<Uint8List> frames, {int w = kAnimW, int h = kAnimH}) async {
    final ble = ref.read(bleControllerProvider.notifier);
    final phase = ref.read(bleControllerProvider).phase;
    if (phase != BleLinkPhase.connected) {
      throw StateError('Connect to Deskbot first');
    }
    await ble.pushLayout(eyes: false, clock: 'off');
    if (mounted) setState(() => _stage = 'Sending to Deskbot… 0%');
    await ble.uploadAnimFrames(
      frames,
      fps: kAnimFps,
      w: w,
      h: h,
      onProgress: (done, total) {
        if (!mounted || total <= 0) return;
        final pct = ((done * 100) / total).clamp(0, 100).round();
        setState(() => _stage = 'Sending to Deskbot… $pct%');
      },
    );
  }

  Future<void> _generateAndPush() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in required')));
      return;
    }
    if ((_quota?.remaining ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daily limit reached (${_quota?.limit ?? 3}/day). Try again tomorrow.')),
      );
      return;
    }
    final prompt = _activePrompt;
    if (prompt.isEmpty) return;

    setState(() {
      _busy = true;
      _stage = 'Queuing on cloud…';
    });

    try {
      await _persistSel();
      final api = ref.read(deskbotCloudApiProvider);
      final created = await api.createLtxJob(
        token,
        prompt: prompt,
        title: _title.text.trim().isEmpty ? _sel.motion.label : _title.text.trim(),
        durationSec: _duration,
      );

      final job = await api.waitLtxJob(
        token,
        created.id,
        onStatus: (s) {
          if (mounted) setState(() => _stage = 'Cloud: $s…');
        },
      );

      final frames = job.decodedFrames();
      if (frames.isEmpty) throw CloudApiException('Job succeeded but no frames returned');

      setState(() => _stage = 'Sending to Deskbot…');
      await _pushFramesToDesk(frames, w: job.frameW, h: job.frameH);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playing on Deskbot — saved to gallery')),
      );
      setState(() => _stage = 'Done');
      await Future.wait([_refreshQuota(), _refreshGallery()]);
      _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generate failed: $e')));
      setState(() => _stage = '');
      await _refreshQuota();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replayJob(LtxJobSummary job) async {
    final token = _token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _stage = 'Loading frames…';
    });
    try {
      final full = await ref.read(deskbotCloudApiProvider).getLtxJob(token, job.id);
      final frames = full.decodedFrames();
      if (frames.isEmpty) throw CloudApiException('No frames for this clip');
      setState(() => _stage = 'Sending to Deskbot…');
      await _pushFramesToDesk(frames, w: full.frameW, h: full.frameH);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${job.title.isEmpty ? "Clip" : job.title} on Deskbot')),
      );
      setState(() => _stage = '');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() => _stage = '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _styleNote.dispose();
    _promptOverride.dispose();
    _title.dispose();
    _characterCustom.dispose();
    _motionCustom.dispose();
    _emotionCustom.dispose();
    _powerCustom.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _customField({
    required TextEditingController controller,
    required String hint,
    required void Function(String) onChanged,
    bool forceShow = false,
  }) {
    if (!forceShow && controller.text.trim().isEmpty) {
      // Still show so user can type without selecting Custom first.
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        enabled: !_busy,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: hint,
          labelText: 'Custom',
          alignLabelWithHint: true,
        ),
        onChanged: onChanged,
      ),
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

  Widget _quotaBanner() {
    final q = _quota;
    final text = Theme.of(context).textTheme;
    final remaining = q?.remaining ?? 3;
    final used = q?.used ?? 0;
    final limit = q?.limit ?? 3;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NovaColors.panelSolid.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: remaining > 0
              ? NovaColors.accent.withValues(alpha: 0.35)
              : NovaColors.bad.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        remaining > 0
            ? 'Today: $used / $limit used · $remaining left'
            : 'Daily limit reached ($limit). Resets tomorrow (UTC).',
        style: text.bodyMedium,
      ),
    );
  }

  Widget _buildCreateTab() {
    final text = Theme.of(context).textTheme;
    final live = _selWithCustoms();
    final canGenerate = !_busy && (_quota?.remaining ?? 1) > 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _quotaBanner(),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        _sectionTitle('Character'),
        _choiceChips(
          choices: ltxCharacters,
          selectedId: _sel.characterId,
          onSelect: (id) {
            if (id != 'custom') _characterCustom.clear();
            _updateSel(_selWithCustoms().copyWith(
              characterId: id,
              characterCustom: id == 'custom' ? _characterCustom.text : '',
            ));
          },
        ),
        _customField(
          controller: _characterCustom,
          hint: 'e.g. tiny raccoon astronaut with LED goggles',
          forceShow: _sel.characterId == 'custom',
          onChanged: (v) => _updateSel(
            _selWithCustoms().copyWith(characterCustom: v, characterId: 'custom'),
          ),
        ),
        _sectionTitle('Motion'),
        _choiceChips(
          choices: ltxMotions,
          selectedId: _sel.motionId,
          onSelect: (id) {
            if (id != 'custom') _motionCustom.clear();
            _updateSel(_selWithCustoms().copyWith(
              motionId: id,
              motionCustom: id == 'custom' ? _motionCustom.text : '',
            ));
          },
        ),
        _customField(
          controller: _motionCustom,
          hint: 'e.g. tosses a paper plane that glides past the camera',
          forceShow: _sel.motionId == 'custom',
          onChanged: (v) => _updateSel(
            _selWithCustoms().copyWith(motionCustom: v, motionId: 'custom'),
          ),
        ),
        _sectionTitle('Emotion'),
        _choiceChips(
          choices: ltxEmotions,
          selectedId: _sel.emotionId,
          onSelect: (id) {
            if (id != 'custom') _emotionCustom.clear();
            _updateSel(_selWithCustoms().copyWith(
              emotionId: id,
              emotionCustom: id == 'custom' ? _emotionCustom.text : '',
            ));
          },
        ),
        _customField(
          controller: _emotionCustom,
          hint: 'e.g. soft hopeful smile, eyes sparkling',
          forceShow: _sel.emotionId == 'custom',
          onChanged: (v) => _updateSel(
            _selWithCustoms().copyWith(emotionCustom: v, emotionId: 'custom'),
          ),
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
                    : (_) {
                        if (p.id != 'custom') _powerCustom.clear();
                        _updateSel(_selWithCustoms().copyWith(
                          powerId: p.id,
                          powerCustom: p.id == 'custom' ? _powerCustom.text : '',
                        ));
                      },
              ),
          ],
        ),
        _customField(
          controller: _powerCustom,
          hint: 'e.g. soft pastel sparks, gentle breeze FX',
          forceShow: _sel.powerId == 'custom',
          onChanged: (v) => _updateSel(
            _selWithCustoms().copyWith(powerCustom: v, powerId: 'custom'),
          ),
        ),
        _sectionTitle('Art style'),
        TextField(
          controller: _styleNote,
          enabled: !_busy,
          decoration: const InputDecoration(hintText: 'manga style, watercolor, neon…'),
          onChanged: (v) => _updateSel(_selWithCustoms().copyWith(styleNote: v)),
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
                        if (!_editPrompt) _promptOverride.text = live.build();
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
            decoration: const InputDecoration(labelText: 'Custom prompt', alignLabelWithHint: true),
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
          onPressed: canGenerate ? _generateAndPush : null,
          child: Text(_busy ? 'Working…' : 'Generate & play on desk'),
        ),
        if (_stage.isNotEmpty) ...[
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(_stage, style: text.bodyMedium?.copyWith(color: NovaColors.accent)),
        ],
      ],
    );
  }

  Widget _buildGalleryTab() {
    final text = Theme.of(context).textTheme;
    if (_loadingGallery && _gallery.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_gallery.isEmpty) {
      return Center(
        child: Text('No generations yet — create one in Create.', style: text.bodyMedium),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshGallery,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: _gallery.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final job = _gallery[i];
          final preview = _previews[job.id];
          final ok = job.status == 'succeeded';
          return Material(
            color: NovaColors.panelSolid.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: (!_busy && ok) ? () => _replayJob(job) : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 72,
                        height: 40,
                        child: preview != null
                            ? Image.memory(preview, fit: BoxFit.cover)
                            : ColoredBox(
                                color: Colors.black26,
                                child: Center(
                                  child: Text(
                                    job.status == 'running' || job.status == 'queued' ? '…' : '—',
                                    style: text.bodySmall,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.title.isEmpty ? 'Untitled' : job.title,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${job.status}${job.createdAt != null ? " · ${job.createdAt!.substring(0, 10)}" : ""}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (ok)
                      IconButton(
                        tooltip: 'Play on desk',
                        onPressed: _busy ? null : () => _replayJob(job),
                        icon: const Icon(Icons.play_circle_outline),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('LTX Studio', style: text.titleLarge),
        backgroundColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Create'),
            Tab(text: 'Gallery'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy
                ? null
                : () async {
                    await Future.wait([_refreshQuota(), _refreshGallery()]);
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildCreateTab(),
            _buildGalleryTab(),
          ],
        ),
      ),
    );
  }
}
