import 'dart:convert';

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

  Future<Map<String, dynamic>> createLtxJob(
    String token, {
    required String prompt,
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
        'duration_sec': durationSec,
      }),
    );
    return _json(res, fallback: 'Could not start generation');
  }

  Future<Map<String, dynamic>> getLtxJob(String token, String jobId) async {
    final res = await _http.get(
      _u('/v1/ltx/jobs/$jobId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return _json(res, fallback: 'Could not load job');
  }

  /// Poll until succeeded/failed. Returns final job map (includes frames_b64).
  Future<Map<String, dynamic>> waitLtxJob(
    String token,
    String jobId, {
    Duration timeout = const Duration(minutes: 12),
    void Function(String status)? onStatus,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final job = await getLtxJob(token, jobId);
      final status = job['status']?.toString() ?? '';
      onStatus?.call(status);
      if (status == 'succeeded') return job;
      if (status == 'failed') {
        throw CloudApiException(job['error']?.toString() ?? 'Generation failed');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw CloudApiException('Timed out waiting for LTX job');
  }
}
