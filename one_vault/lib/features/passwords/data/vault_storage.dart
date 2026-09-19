import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<File> _file(int userId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/passwords_$userId.json');
  }

  Future<void> clearPasswords(int userId) async {
    try {
      final file = await _file(userId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
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
