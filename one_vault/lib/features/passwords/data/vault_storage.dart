import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_models.dart';

enum VaultAutoLock { immediately, oneMinute, fiveMinutes, fifteenMinutes }

extension VaultAutoLockLabel on VaultAutoLock {
  String get label => switch (this) {
    VaultAutoLock.immediately => 'Immediately',
    VaultAutoLock.oneMinute => '1 minute',
    VaultAutoLock.fiveMinutes => '5 minutes',
    VaultAutoLock.fifteenMinutes => '15 minutes',
  };

  Duration? get duration => switch (this) {
    VaultAutoLock.immediately => Duration.zero,
    VaultAutoLock.oneMinute => const Duration(minutes: 1),
    VaultAutoLock.fiveMinutes => const Duration(minutes: 5),
    VaultAutoLock.fifteenMinutes => const Duration(minutes: 15),
  };
}

class VaultLocalStore {
  VaultLocalStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _secure;

  Future<File> _file(int userId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/vault_$userId.json');
  }

  Future<VaultSnapshot> readSnapshot(int userId) async {
    try {
      final file = await _file(userId);
      if (!await file.exists()) return const VaultSnapshot();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) return VaultSnapshot.fromJson(raw);
      return const VaultSnapshot();
    } catch (_) {
      return const VaultSnapshot();
    }
  }

  Future<void> writeSnapshot(int userId, VaultSnapshot snapshot) async {
    final file = await _file(userId);
    await file.writeAsString(jsonEncode(snapshot.toJson()));
  }

  Future<void> saveDek(int userId, List<int> dekBytes) {
    return _secure.write(key: 'vault_dek_$userId', value: base64Encode(dekBytes));
  }

  Future<List<int>?> readDek(int userId) async {
    final raw = await _secure.read(key: 'vault_dek_$userId');
    if (raw == null || raw.isEmpty) return null;
    return base64Decode(raw);
  }

  Future<void> clearDek(int userId) {
    return _secure.delete(key: 'vault_dek_$userId');
  }

  Future<bool> biometricEnabled(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('vault_biometric_$userId') ?? false;
  }

  Future<void> setBiometricEnabled(int userId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vault_biometric_$userId', value);
  }

  Future<VaultAutoLock> autoLock(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('vault_autolock_$userId');
    return VaultAutoLock.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => VaultAutoLock.oneMinute,
    );
  }

  Future<void> setAutoLock(int userId, VaultAutoLock value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vault_autolock_$userId', value.name);
  }
}
