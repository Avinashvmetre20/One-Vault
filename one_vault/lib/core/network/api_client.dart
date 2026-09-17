import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
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
      request: () => _client.get(_uri(path, query), headers: headers),
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

  Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(
      method: 'PATCH',
      path: path,
      request: () => _client.patch(_uri(path), headers: headers, body: body),
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
      request: () => _client.put(_uri(path), headers: headers, body: body),
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
      request: () => _client.delete(_uri(path), headers: headers, body: body),
    );
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    required Future<http.Response> Function() request,
  }) async {
    final startedAt = DateTime.now();
    final url = '${ApiConfig.baseUrl}$path';
    try {
      final response = await request().timeout(_timeout);
      final ms = DateTime.now().difference(startedAt).inMilliseconds;
      final line = '$method $url ${response.statusCode} ${ms}ms';
      debugPrint(response.statusCode >= 400 ? 'ERROR $line' : line);
      return response;
    } catch (error) {
      final ms = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint('ERROR $method $url ${ms}ms $error');
      rethrow;
    }
  }
}
