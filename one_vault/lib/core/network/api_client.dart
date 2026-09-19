import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'device_time_zone.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    this.refreshAccessToken,
    this.accessToken,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Future<bool> Function()? refreshAccessToken;
  final String? Function()? accessToken;
  static const _timeout = Duration(seconds: 25);
  static Future<void>? _resolving;

  static Map<String, String> authHeaders(String? token, {bool json = false}) {
    return {
      'Authorization': 'Bearer ${token ?? ''}',
      'X-Timezone': DeviceTimeZone.current,
      if (json) 'Content-Type': 'application/json',
    };
  }

  static Map<String, dynamic> decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> readJson(
    Future<http.Response> Function() request, {
    required Exception Function(String message, int statusCode) onError,
  }) async {
    final response = await request();
    final json = decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return json;
    throw onError(
      (json['message'] as String?) ?? 'Request failed',
      response.statusCode,
    );
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalized');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        ...query,
      },
    );
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? query,
  }) {
    return _send(
      method: 'GET',
      path: path,
      request: () => _client.get(_uri(path, query), headers: _withTimeZone(headers)),
    );
  }

  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      method: 'POST',
      path: path,
      request: () => _client.post(_uri(path), headers: _withTimeZone(headers), body: body),
    );
  }

  Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      method: 'PATCH',
      path: path,
      request: () => _client.patch(_uri(path), headers: _withTimeZone(headers), body: body),
    );
  }

  Future<http.Response> put(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      method: 'PUT',
      path: path,
      request: () => _client.put(_uri(path), headers: _withTimeZone(headers), body: body),
    );
  }

  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      method: 'DELETE',
      path: path,
      request: () => _client.delete(_uri(path), headers: _withTimeZone(headers), body: body),
    );
  }

  Future<bool> checkHealth() async {
    try {
      final response = await get('/health');
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      return decode(response)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _withTimeZone(Map<String, String>? headers) {
    final token = accessToken?.call();
    return {
      'X-Timezone': DeviceTimeZone.current,
      ...?headers,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _ensureBaseUrl() {
    final resolving = _resolving;
    if (resolving != null) return resolving;
    final future = _pickReachableBase();
    _resolving = future;
    return future;
  }

  Future<void> _pickReachableBase() async {
    final urls = ApiConfig.candidateUrls;
    final reachable = await Future.wait(urls.map(_isReachable));
    for (var i = 0; i < urls.length; i++) {
      if (!reachable[i]) continue;
      ApiConfig.use(urls[i]);
      _log('API base ${urls[i]}', isError: false);
      return;
    }
    ApiConfig.use(ApiConfig.baseUrl);
  }

  Future<bool> _isReachable(String base) async {
    try {
      final url = '${base.replaceAll(RegExp(r'/+$'), '')}/health';
      final response = await _client.get(Uri.parse(url)).timeout(
        const Duration(seconds: 2),
      );
      return response.statusCode > 0;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    required Future<http.Response> Function() request,
  }) async {
    await _ensureBaseUrl();
    final startedAt = DateTime.now();
    final url = _uri(path).toString();
    try {
      var response = await request().timeout(_timeout);
      if (response.statusCode == 401 &&
          !path.startsWith('/api/auth/') &&
          refreshAccessToken != null) {
        final refreshed = await refreshAccessToken!();
        if (refreshed) {
          response = await request().timeout(_timeout);
        }
      }
      _log(
        '$method $url ${response.statusCode} ${DateTime.now().difference(startedAt).inMilliseconds}ms',
        isError: response.statusCode >= 400,
      );
      return response;
    } catch (error) {
      _log(
        '$method $url ${DateTime.now().difference(startedAt).inMilliseconds}ms $error',
        isError: true,
      );
      rethrow;
    }
  }

  void _log(String line, {required bool isError}) {
    if (!kDebugMode) return;
    debugPrint(isError ? 'ERROR $line' : line);
  }
}
