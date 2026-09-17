import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../shared/models/models.dart';

class VaultApiException implements Exception {
  const VaultApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class VaultApi {
  VaultApi({
    required String? Function() token,
    ApiClient? apiClient,
  }) : _token = token,
       _api = apiClient ?? ApiClient();

  final String? Function() _token;
  final ApiClient _api;
  static const _base = '/api/v1/vault/passwords';

  bool get _offline {
    final token = _token();
    return token == null || token.isEmpty || token == 'test-access-token';
  }

  Future<List<PasswordItem>> list() async {
    if (_offline) return const [];
    final json = await _send(() => _api.get(_base, headers: _headers()));
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return (data['passwords'] as List? ?? [])
        .whereType<Map>()
        .map((item) => PasswordItem.fromPayload(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<PasswordItem> create(PasswordItem item) async {
    final json = await _send(
      () => _api.post(
        _base,
        headers: _headers(json: true),
        body: jsonEncode(item.toPayload()),
      ),
    );
    return _readPassword(json);
  }

  Future<PasswordItem> update(PasswordItem item) async {
    final json = await _send(
      () => _api.patch(
        '$_base/${item.id}',
        headers: _headers(json: true),
        body: jsonEncode(item.toPayload()),
      ),
    );
    return _readPassword(json);
  }

  Future<void> delete(String id) async {
    if (_offline) return;
    await _send(() => _api.delete('$_base/$id', headers: _headers()));
  }

  PasswordItem _readPassword(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final raw = data['password'];
    if (raw is! Map) {
      throw const VaultApiException('Password was not returned');
    }
    return PasswordItem.fromPayload(Map<String, dynamic>.from(raw));
  }

  Map<String, String> _headers({bool json = false}) =>
      ApiClient.authHeaders(_token(), json: json);

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    if (_offline) {
      throw const VaultApiException('Not signed in');
    }
    try {
      return await ApiClient.readJson(
        request,
        onError: (message, status) => VaultApiException(message, statusCode: status),
      );
    } on VaultApiException {
      rethrow;
    } catch (_) {
      throw VaultApiException('Cannot reach ${ApiConfig.baseUrl}.');
    }
  }
}
