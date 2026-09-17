import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MpinException implements Exception {
  const MpinException(this.message);
  final String message;

  @override
  String toString() => message;
}

class MpinStorage {
  MpinStorage({FlutterSecureStorage? secureStorage})
    : _secure =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _secure;
  static const maxAttempts = 3;
  static const pinLength = 4;
  static final _sha = Sha256();

  String _hashKey(int userId) => 'mpin_hash_$userId';
  String _saltKey(int userId) => 'mpin_salt_$userId';
  String _attemptsKey(int userId) => 'mpin_attempts_$userId';
  String _biometricKey(int userId) => 'mpin_biometric_$userId';

  bool isValidPin(String pin) =>
      pin.length == pinLength && RegExp(r'^\d+$').hasMatch(pin);

  Future<bool> hasPin(int userId) async {
    final parts = await Future.wait([
      _secure.read(key: _hashKey(userId)),
      _secure.read(key: _saltKey(userId)),
    ]);
    final hash = parts[0];
    final salt = parts[1];
    return hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  Future<void> save(int userId, String pin) async {
    final saltBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt = base64Encode(saltBytes);
    final hash = await _hash(pin, salt);
    await _secure.write(key: _saltKey(userId), value: salt);
    await _secure.write(key: _hashKey(userId), value: hash);
    await resetAttempts(userId);
  }

  Future<bool> verify(int userId, String pin) async {
    final salt = await _secure.read(key: _saltKey(userId));
    final expected = await _secure.read(key: _hashKey(userId));
    if (salt == null || expected == null) return false;
    final actual = await _hash(pin, salt);
    return actual == expected;
  }

  Future<int> attempts(int userId) async {
    final raw = await _secure.read(key: _attemptsKey(userId));
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<int> incrementAttempts(int userId) async {
    final next = await attempts(userId) + 1;
    await _secure.write(key: _attemptsKey(userId), value: '$next');
    return next;
  }

  Future<void> resetAttempts(int userId) async {
    await _secure.delete(key: _attemptsKey(userId));
  }

  Future<bool> biometricEnabled(int userId) async {
    return await _secure.read(key: _biometricKey(userId)) == '1';
  }

  Future<void> setBiometricEnabled(int userId, bool value) async {
    if (value) {
      await _secure.write(key: _biometricKey(userId), value: '1');
    } else {
      await _secure.delete(key: _biometricKey(userId));
    }
  }

  Future<void> clear(int userId) async {
    await _secure.delete(key: _hashKey(userId));
    await _secure.delete(key: _saltKey(userId));
    await _secure.delete(key: _attemptsKey(userId));
    await _secure.delete(key: _biometricKey(userId));
  }

  Future<String> _hash(String pin, String salt) async {
    final digest = await _sha.hash(utf8.encode('$salt:$pin'));
    return base64Encode(digest.bytes);
  }
}
