import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';

class SavedSession {
  const SavedSession({required this.tokens, this.user});

  final AuthTokens tokens;
  final AuthUser? user;
}

class AuthStorage {
  AuthStorage({FlutterSecureStorage? secureStorage})
    : _secure =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _secure;

  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _userKey = 'auth_user';

  Future<void> save(AuthTokens tokens, {AuthUser? user}) async {
    await _secure.write(key: _accessKey, value: tokens.accessToken);
    await _secure.write(key: _refreshKey, value: tokens.refreshToken);
    if (user != null) {
      await _secure.write(key: _userKey, value: jsonEncode(user.toJson()));
    }
    await _clearLegacyPrefs();
  }

  Future<SavedSession?> read() async {
    final parts = await Future.wait([
      _secure.read(key: _accessKey),
      _secure.read(key: _refreshKey),
      _secure.read(key: _userKey),
    ]);
    var accessToken = parts[0];
    var refreshToken = parts[1];
    var rawUser = parts[2];

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      final migrated = await _readLegacyPrefs();
      if (migrated == null) return null;
      await save(migrated.tokens, user: migrated.user);
      return migrated;
    }

    AuthUser? user;
    if (rawUser != null && rawUser.isNotEmpty) {
      user = AuthUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
    }

    return SavedSession(
      tokens: AuthTokens(accessToken: accessToken, refreshToken: refreshToken),
      user: user,
    );
  }

  Future<void> clear() async {
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    await _secure.delete(key: _userKey);
    await _clearLegacyPrefs();
  }

  Future<SavedSession?> _readLegacyPrefs() async {
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

  Future<void> _clearLegacyPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }
}
