import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import 'vault_models.dart';

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
  static const _base = '/api/v1/vault';

  bool get _offline {
    final token = _token();
    return token == null || token.isEmpty || token == 'test-access-token';
  }

  Future<VaultMeta?> meta() async {
    if (_offline) return null;
    final json = await _send(() => _api.get('$_base/meta', headers: _headers()));
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final meta = data['meta'];
    if (meta is Map<String, dynamic>) return VaultMeta.fromJson(meta);
    return null;
  }

  Future<void> putMeta(VaultMeta meta) async {
    if (_offline) return;
    await _send(
      () => _api.put(
        '$_base/meta',
        headers: _jsonHeaders(),
        body: jsonEncode(meta.toJson()),
      ),
    );
  }

  Future<List<EncryptedCredential>> credentials({bool includeDeleted = true}) async {
    if (_offline) return const [];
    final json = await _send(
      () => _api.get(
        '$_base/credentials',
        headers: _headers(),
        query: {'includeDeleted': includeDeleted ? 'true' : 'false'},
      ),
    );
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return (data['credentials'] as List? ?? [])
        .whereType<Map>()
        .map((item) => EncryptedCredential.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> upsert(EncryptedCredential credential) async {
    if (_offline) return;
    await _send(
      () => _api.put(
        '$_base/credentials/${credential.id}',
        headers: _jsonHeaders(),
        body: jsonEncode({
          'encryptedPayload': credential.encryptedPayload,
          'nonce': credential.nonce,
          'version': credential.version,
          if (credential.deletedAt != null)
            'deletedAt': credential.deletedAt!.toIso8601String(),
        }),
      ),
    );
  }

  Future<void> delete(String id) async {
    if (_offline) return;
    await _send(() => _api.delete('$_base/credentials/$id', headers: _headers()));
  }

  Map<String, String> _headers() => {
    'Authorization': 'Bearer ${_token() ?? ''}',
  };

  Map<String, String> _jsonHeaders() => {
    ..._headers(),
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request();
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      throw VaultApiException(
        (decoded['message'] as String?) ?? 'Request failed',
        statusCode: response.statusCode,
      );
    } on VaultApiException {
      rethrow;
    } catch (_) {
      throw VaultApiException('Cannot reach ${ApiConfig.baseUrl}.');
    }
  }
}
