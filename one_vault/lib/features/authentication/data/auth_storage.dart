import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';

class SavedSession {
  const SavedSession({required this.tokens, this.user});

  final AuthTokens tokens;
  final AuthUser? user;
}

class AuthStorage {
  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _userKey = 'auth_user';

  Future<void> save(AuthTokens tokens, {AuthUser? user}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, tokens.accessToken);
    await prefs.setString(_refreshKey, tokens.refreshToken);
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    }
  }

  Future<SavedSession?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessKey);
    final refreshToken = prefs.getString(_refreshKey);
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      return null;
    }

    AuthUser? user;
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      user = AuthUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
    }

    return SavedSession(
      tokens: AuthTokens(accessToken: accessToken, refreshToken: refreshToken),
      user: user,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }
}
