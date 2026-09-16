import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
  }) {
    return _send(
      method: 'GET',
      path: path,
      request: () => _client.get(_uri(path), headers: headers),
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
      request: () => _client.post(_uri(path), headers: headers, body: body),
    );
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    required Future<http.Response> Function() request,
  }) async {
    final startedAt = DateTime.now();
    try {
      final response = await request().timeout(_timeout);
      _log(method, path, startedAt);
      return response;
    } catch (_) {
      _log(method, path, startedAt);
      rethrow;
    }
  }

  void _log(String method, String path, DateTime startedAt) {
    final ms = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint('$method ${ApiConfig.baseUrl}$path ${ms}ms');
  }
}
