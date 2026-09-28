import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_store.dart';

class CloudApiException implements Exception {
  CloudApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class LtxQuota {
  const LtxQuota({
    required this.limit,
    required this.used,
    required this.remaining,
    required this.resetsAt,
  });

  final int limit;
  final int used;
  final int remaining;
  final String resetsAt;

  factory LtxQuota.fromJson(Map<String, dynamic> j) => LtxQuota(
        limit: (j['limit'] as num?)?.toInt() ?? 3,
        used: (j['used'] as num?)?.toInt() ?? 0,
        remaining: (j['remaining'] as num?)?.toInt() ?? 0,
        resetsAt: j['resets_at']?.toString() ?? '',
      );
}

class LtxJobSummary {
  const LtxJobSummary({
    required this.id,
    required this.status,
    required this.prompt,
    required this.title,
    required this.durationSec,
    this.error,
    this.frameW = 96,
    this.frameH = 52,
    this.frameCount = 0,
    this.previewUrl,
    this.videoUrl,
    this.createdAt,
    this.finishedAt,
    this.framesB64,
  });

  final String id;
  final String status;
  final String prompt;
  final String title;
  final int durationSec;
  final String? error;
  final int frameW;
  final int frameH;
  final int frameCount;
  final String? previewUrl;
  final String? videoUrl;
  final String? createdAt;
  final String? finishedAt;
  final List<String>? framesB64;

  factory LtxJobSummary.fromJson(Map<String, dynamic> j) => LtxJobSummary(
        id: j['id']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        prompt: j['prompt']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        durationSec: (j['duration_sec'] as num?)?.toInt() ?? 4,
        error: j['error']?.toString(),
        frameW: (j['frame_w'] as num?)?.toInt() ?? 96,
        frameH: (j['frame_h'] as num?)?.toInt() ?? 52,
        frameCount: (j['frame_count'] as num?)?.toInt() ?? 0,
        previewUrl: j['preview_url']?.toString(),
        videoUrl: j['video_url']?.toString(),
        createdAt: j['created_at']?.toString(),
        finishedAt: j['finished_at']?.toString(),
        framesB64: (j['frames_b64'] as List?)?.map((e) => e.toString()).toList(),
      );

  List<Uint8List> decodedFrames() {
    final list = framesB64;
    if (list == null || list.isEmpty) return const [];
    return [for (final item in list) Uint8List.fromList(base64Decode(item))];
  }
}

class DeskbotCloudApi {
  DeskbotCloudApi({
    http.Client? client,
    this.baseUrl = kDeskbotApiBase,
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _json(
    http.Response res, {
    String fallback = 'Request failed',
  }) async {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = body?['detail'];
      final msg = detail is String
          ? detail
          : (detail != null ? detail.toString() : (body?['message']?.toString() ?? fallback));
      throw CloudApiException(msg, statusCode: res.statusCode);
    }
    return body ?? <String, dynamic>{};
  }

  Future<List<dynamic>> _jsonList(http.Response res, {String fallback = 'Request failed'}) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw CloudApiException(detail?.toString() ?? fallback, statusCode: res.statusCode);
    }
    if (decoded is! List) throw CloudApiException(fallback);
    return decoded;
  }

  Future<({String token, CloudUser user})> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final res = await _http.post(
      _u('/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'display_name': displayName.trim(),
      }),
    );
    final j = await _json(res, fallback: 'Register failed');
    return (
      token: j['access_token'] as String,
      user: CloudUser.fromJson(j),
    );
  }

  Future<({String token, CloudUser user})> login({
    required String email,
    required String password,
  }) async {
    final res = await _http.post(
      _u('/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );
    final j = await _json(res, fallback: 'Login failed');
    return (
      token: j['access_token'] as String,
      user: CloudUser.fromJson(j),
    );
  }

  Future<CloudUser> me(String token) async {
    final res = await _http.get(
      _u('/v1/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = await _json(res, fallback: 'Session expired');
    return CloudUser.fromJson(j);
  }

  Future<CloudUser> updateMe(String token, {required String displayName}) async {
    final res = await _http.patch(
      _u('/v1/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'display_name': displayName}),
    );
    final j = await _json(res, fallback: 'Update failed');
    return CloudUser.fromJson(j);
  }

  Future<LtxQuota> getLtxQuota(String token) async {
    final res = await _http.get(
      _u('/v1/ltx/quota'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = await _json(res, fallback: 'Could not load quota');
    return LtxQuota.fromJson(j);
  }

  Future<LtxJobSummary> createLtxJob(
    String token, {
    required String prompt,
    String title = '',
    int durationSec = 4,
  }) async {
    final res = await _http.post(
      _u('/v1/ltx/jobs'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prompt': prompt,
        'title': title,
        'duration_sec': durationSec,
      }),
    );
    final j = await _json(res, fallback: 'Could not start generation');
    return LtxJobSummary.fromJson(j);
  }

  Future<LtxJobSummary> getLtxJob(String token, String jobId) async {
    final res = await _http.get(
      _u('/v1/ltx/jobs/$jobId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final j = await _json(res, fallback: 'Could not load job');
    return LtxJobSummary.fromJson(j);
  }

  Future<List<LtxJobSummary>> listLtxJobs(
    String token, {
    String? status,
    int limit = 30,
  }) async {
    final qp = <String, String>{'limit': '$limit'};
    if (status != null && status.isNotEmpty) qp['status'] = status;
    final res = await _http.get(
      _u('/v1/ltx/jobs').replace(queryParameters: qp),
      headers: {'Authorization': 'Bearer $token'},
    );
    final list = await _jsonList(res, fallback: 'Could not load gallery');
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) LtxJobSummary.fromJson(item),
    ];
  }

  Future<Uint8List> fetchPreviewBytes(String token, String jobId) async {
    final res = await _http.get(
      _u('/v1/ltx/jobs/$jobId/preview'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CloudApiException('Preview failed', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  /// Poll until succeeded/failed.
  Future<LtxJobSummary> waitLtxJob(
    String token,
    String jobId, {
    Duration timeout = const Duration(minutes: 12),
    void Function(String status)? onStatus,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final job = await getLtxJob(token, jobId);
      onStatus?.call(job.status);
      if (job.status == 'succeeded') return job;
      if (job.status == 'failed') {
        throw CloudApiException(job.error ?? 'Generation failed');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw CloudApiException('Timed out waiting for LTX job');
  }
}
