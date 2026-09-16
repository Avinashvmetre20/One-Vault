import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import 'auth_models.dart';

class AuthService {
  AuthService({http.Client? client, ApiClient? apiClient})
    : _api = apiClient ?? ApiClient(client: client);

  final ApiClient _api;

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) {
    return _authPost(
      '/api/auth/register',
      {
        'name': name,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) {
    return _authPost('/api/auth/login', {
      'email': email,
      'password': password,
    });
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _send(
      () => _api.post(
        '/api/auth/refresh',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ),
    );
    final data = json['data'] as Map<String, dynamic>;
    return AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>);
  }

  Future<AuthUser> me(String accessToken) async {
    final json = await _send(
      () => _api.get(
        '/api/auth/me',
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
    final data = json['data'] as Map<String, dynamic>;
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout(String refreshToken) async {
    await _send(
      () => _api.post(
        '/api/auth/logout',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ),
    );
  }

  Future<AuthResult> _authPost(String path, Map<String, dynamic> body) async {
    final json = await _send(
      () => _api.post(
        path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return AuthResult.fromJson(json);
  }

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

      throw AuthException(
        (decoded['message'] as String?) ?? 'Request failed',
        statusCode: response.statusCode,
      );
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw AuthException(
        'Request timed out for ${ApiConfig.baseUrl}. The phone could not reach the API.',
      );
    } catch (_) {
      throw AuthException(
        'Cannot reach ${ApiConfig.baseUrl}. Check Wi-Fi and that the API is running.',
      );
    }
  }
}
