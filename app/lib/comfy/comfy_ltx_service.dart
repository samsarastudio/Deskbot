import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../desk/manga_library.dart';
import '../desk/scenery_encode.dart';

/// Node IDs from assets/comfy/video_ltx2_5_t2v.json (API export).
const String kLtxPromptNode = '405:376';
const String kLtxDurationNode = '405:362';
const String kLtxFpsNode = '405:361';
const String kLtxEnhanceNode = '405:383';
const String kLtxSaveVideoNode = '75';
const String kLtxDecodeNode = '405:374';

const String kComfyCloudBase = 'https://cloud.comfy.org';
const String kLtxWorkflowAsset = 'assets/comfy/video_ltx2_5_t2v.json';

class ComfyCloudException implements Exception {
  ComfyCloudException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

typedef ComfyProgress = void Function(String stage);

/// Runs LTX-2.5 T2V on Comfy Cloud from the phone, then encodes Deskbot frames.
class ComfyLtxService {
  ComfyLtxService({http.Client? httpClient, this.baseUrl = kComfyCloudBase})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  Map<String, String> _headers(String apiKey) => {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _loadWorkflow() async {
    final raw = await rootBundle.loadString(kLtxWorkflowAsset);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Map<String, dynamic> _patchWorkflow(
    Map<String, dynamic> workflow, {
    required String prompt,
    int durationSec = 4,
    int fps = 24,
    bool enhance = false,
  }) {
    final wf = jsonDecode(jsonEncode(workflow)) as Map<String, dynamic>;

    void setInput(String nodeId, String field, Object value) {
      final node = wf[nodeId] as Map<String, dynamic>?;
      if (node == null) return;
      final inputs = (node['inputs'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      inputs[field] = value;
      node['inputs'] = inputs;
    }

    setInput(kLtxPromptNode, 'value', prompt);
    setInput(kLtxDurationNode, 'value', durationSec);
    setInput(kLtxFpsNode, 'value', fps);
    setInput(kLtxEnhanceNode, 'value', enhance);
    return wf;
  }

  Future<String> submit({
    required String apiKey,
    required String prompt,
    int durationSec = 4,
    int fps = 24,
    bool enhance = false,
  }) async {
    final workflow = _patchWorkflow(
      await _loadWorkflow(),
      prompt: prompt,
      durationSec: durationSec,
      fps: fps,
      enhance: enhance,
    );

    final uri = Uri.parse('$baseUrl/api/prompt');
    final res = await _http.post(
      uri,
      headers: _headers(apiKey),
      body: jsonEncode({'prompt': workflow}),
    );
    if (res.statusCode == 401) {
      throw ComfyCloudException('Invalid Comfy API key', statusCode: 401);
    }
    if (res.statusCode == 402) {
      throw ComfyCloudException('Insufficient Comfy Cloud credits', statusCode: 402);
    }
    if (res.statusCode == 429) {
      throw ComfyCloudException('Comfy subscription inactive or rate limited', statusCode: 429);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ComfyCloudException('Submit failed (${res.statusCode}): ${res.body}', statusCode: res.statusCode);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['error'] != null) {
      throw ComfyCloudException('Workflow error: ${body['error']}');
    }
    final id = body['prompt_id']?.toString();
    if (id == null || id.isEmpty) {
      throw ComfyCloudException('No prompt_id in response: ${res.body}');
    }
    return id;
  }

  Future<void> waitUntilDone(String apiKey, String promptId, {Duration timeout = const Duration(minutes: 8)}) async {
    const terminalOk = {'success'};
    const terminalFail = {'error', 'non_retryable_error', 'lost', 'cancelled'};
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final uri = Uri.parse('$baseUrl/api/job/$promptId/status');
      final res = await _http.get(uri, headers: {'X-API-Key': apiKey});
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ComfyCloudException('Status failed (${res.statusCode}): ${res.body}', statusCode: res.statusCode);
      }
      final status = (jsonDecode(res.body) as Map<String, dynamic>)['status']?.toString() ?? '';
      if (terminalOk.contains(status)) return;
      if (terminalFail.contains(status)) {
        throw ComfyCloudException('Job $promptId failed: $status');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw ComfyCloudException('Timed out waiting for job $promptId');
  }

  Future<Map<String, dynamic>> history(String apiKey, String promptId) async {
    final uri = Uri.parse('$baseUrl/api/history/$promptId');
    final res = await _http.get(uri, headers: {'X-API-Key': apiKey});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ComfyCloudException('History failed (${res.statusCode}): ${res.body}', statusCode: res.statusCode);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final entry = body[promptId] as Map<String, dynamic>?;
    if (entry == null) {
      throw ComfyCloudException('No history for $promptId');
    }
    return entry;
  }

  Future<Uint8List> downloadView({
    required String apiKey,
    required String filename,
    String subfolder = '',
    String type = 'output',
  }) async {
    final params = {
      'filename': filename,
      'subfolder': subfolder,
      'type': type,
    };
    final uri = Uri.parse('$baseUrl/api/view').replace(queryParameters: params);

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set('X-API-Key', apiKey);
      req.followRedirects = false;
      final res = await req.close();
      if (res.statusCode == 302 || res.statusCode == 301) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) {
          throw ComfyCloudException('Missing redirect for $filename');
        }
        // Signed URL — no API key header.
        final fileRes = await _http.get(Uri.parse(loc));
        if (fileRes.statusCode < 200 || fileRes.statusCode >= 300) {
          throw ComfyCloudException('Download failed (${fileRes.statusCode})');
        }
        return fileRes.bodyBytes;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final err = await res.transform(utf8.decoder).join();
        throw ComfyCloudException('View failed (${res.statusCode}): $err', statusCode: res.statusCode);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  List<Map<String, String>> _fileRefsFromOutputs(Map<String, dynamic> outputs, String nodeId) {
    final nodeOut = outputs[nodeId];
    if (nodeOut is! Map) return <Map<String, String>>[];
    final refs = <Map<String, String>>[];
    for (final key in ['images', 'gifs', 'videos', 'files']) {
      final list = nodeOut[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final name = item['filename']?.toString();
        if (name == null || name.isEmpty) continue;
        refs.add({
          'filename': name,
          'subfolder': item['subfolder']?.toString() ?? '',
          'type': item['type']?.toString() ?? 'output',
        });
      }
    }
    return refs;
  }

  /// Full pipeline: prompt → Cloud LTX → RGB565 frames for Deskbot.
  Future<List<Uint8List>> generateDeskFrames({
    required String apiKey,
    required String prompt,
    int durationSec = 4,
    int fps = 24,
    bool enhance = false,
    ComfyProgress? onProgress,
  }) async {
    onProgress?.call('Submitting to Comfy Cloud…');
    final promptId = await submit(
      apiKey: apiKey,
      prompt: prompt,
      durationSec: durationSec,
      fps: fps,
      enhance: enhance,
    );

    onProgress?.call('Generating LTX video…');
    await waitUntilDone(apiKey, promptId);

    onProgress?.call('Downloading…');
    final hist = await history(apiKey, promptId);
    final outputs = (hist['outputs'] as Map<String, dynamic>?) ?? {};

    // Prefer decoded image sequence if Cloud exposed it.
    final imageRefs = _fileRefsFromOutputs(outputs, kLtxDecodeNode)
        .where((r) {
          final n = r['filename']!.toLowerCase();
          return n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.webp');
        })
        .toList();

    if (imageRefs.length >= 2) {
      onProgress?.call('Encoding frames…');
      final step = imageRefs.length <= kAnimMaxFrames ? 1 : (imageRefs.length / kAnimMaxFrames).ceil();
      final picked = <Map<String, String>>[];
      for (var i = 0; i < imageRefs.length && picked.length < kAnimMaxFrames; i += step) {
        picked.add(imageRefs[i]);
      }
      final frames = <Uint8List>[];
      for (final ref in picked) {
        final bytes = await downloadView(
          apiKey: apiKey,
          filename: ref['filename']!,
          subfolder: ref['subfolder'] ?? '',
          type: ref['type'] ?? 'output',
        );
        frames.add(encodeImageBytesToAnimFrame(bytes));
      }
      if (frames.isNotEmpty) return frames;
    }

    final videoRefs = <Map<String, String>>[
      ..._fileRefsFromOutputs(outputs, kLtxSaveVideoNode),
    ];
    if (videoRefs.isEmpty) {
      for (final entry in outputs.entries) {
        videoRefs.addAll(_fileRefsFromOutputs(outputs, entry.key));
      }
    }
    if (videoRefs.isEmpty) {
      throw ComfyCloudException('No video/image outputs in job history');
    }

    final ref = videoRefs.first;
    final videoBytes = await downloadView(
      apiKey: apiKey,
      filename: ref['filename']!,
      subfolder: ref['subfolder'] ?? '',
      type: ref['type'] ?? 'output',
    );

    final name = ref['filename']!.toLowerCase();
    if (name.endsWith('.gif') || name.endsWith('.webp')) {
      onProgress?.call('Encoding GIF frames…');
      return encodeGifToAnimFrames(videoBytes);
    }

    onProgress?.call('Sampling video frames…');
    return _framesFromVideoFile(videoBytes, filename: ref['filename']!, durationSec: durationSec);
  }

  Future<List<Uint8List>> _framesFromVideoFile(
    Uint8List videoBytes, {
    required String filename,
    int durationSec = 4,
  }) async {
    final dir = await getTemporaryDirectory();
    final ext = p.extension(filename).isEmpty ? '.mp4' : p.extension(filename);
    final file = File(p.join(dir.path, 'nova_ltx_${DateTime.now().millisecondsSinceEpoch}$ext'));
    await file.writeAsBytes(videoBytes, flush: true);

    try {
      final durationMs = durationSecToSampleMs(durationSec);
      final times = <int>[
        for (var i = 0; i < kAnimMaxFrames; i++)
          kAnimMaxFrames == 1 ? 0 : (durationMs * i / (kAnimMaxFrames - 1)).round(),
      ];
      final frames = <Uint8List>[];
      for (final t in times) {
        final thumb = await VideoThumbnail.thumbnailData(
          video: file.path,
          imageFormat: ImageFormat.PNG,
          timeMs: t,
          quality: 85,
        );
        if (thumb == null) continue;
        frames.add(encodeImageBytesToAnimFrame(thumb));
      }
      if (frames.isEmpty) {
        throw ComfyCloudException('Could not extract frames from video');
      }
      return frames;
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

int durationSecToSampleMs(int sec) => (sec * 1000).clamp(1000, 8000);

Uint8List encodeImageBytesToAnimFrame(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode frame image');
  }
  final resized = img.copyResize(
    decoded,
    width: kAnimW,
    height: kAnimH,
    interpolation: img.Interpolation.average,
  );
  return encodeImageToRgb565(resized);
}
