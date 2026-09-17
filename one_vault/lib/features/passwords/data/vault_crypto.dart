import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class VaultCiphertext {
  const VaultCiphertext({required this.nonce, required this.payload});

  final String nonce;
  final String payload;
}

class VaultKeySet {
  const VaultKeySet({
    required this.dek,
    required this.salt,
    required this.wrappedDek,
    required this.wrappedDekNonce,
    this.kdf = 'argon2id',
    this.kdfMemory = 8192,
    this.kdfIterations = 3,
    this.kdfParallelism = 1,
  });

  final SecretKey dek;
  final String salt;
  final String wrappedDek;
  final String wrappedDekNonce;
  final String kdf;
  final int kdfMemory;
  final int kdfIterations;
  final int kdfParallelism;
}

Future<List<int>> deriveVaultKeyBytes(Map<String, Object> args) async {
  final key = await Argon2id(
    parallelism: args['parallelism'] as int,
    memory: args['memory'] as int,
    iterations: args['iterations'] as int,
    hashLength: 32,
  ).deriveKeyFromPassword(
    password: args['password'] as String,
    nonce: List<int>.from(args['salt'] as List),
  );
  return key.extractBytes();
}

class VaultCrypto {
  VaultCrypto._();

  static final _aes = AesGcm.with256bits();

  static Future<SecretKey> deriveKek({
    required String masterPassword,
    required List<int> salt,
    int memory = 8192,
    int iterations = 3,
    int parallelism = 1,
  }) async {
    final args = <String, Object>{
      'password': masterPassword,
      'salt': List<int>.from(salt),
      'memory': memory,
      'iterations': iterations,
      'parallelism': parallelism,
    };
    final bytes = await Isolate.run(() => deriveVaultKeyBytes(args));
    return SecretKey(bytes);
  }

  static Future<SecretKey> newDek() => _aes.newSecretKey();

  static List<int> newSalt() => _aes.newNonce() + _aes.newNonce();

  static Future<VaultCiphertext> encryptString(
    String plaintext,
    SecretKey key,
  ) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return VaultCiphertext(
      nonce: base64Encode(nonce),
      payload: base64Encode([...box.cipherText, ...box.mac.bytes]),
    );
  }

  static Future<String> decryptString(
    VaultCiphertext ciphertext,
    SecretKey key,
  ) async {
    final blob = base64Decode(ciphertext.payload);
    if (blob.length < 16) {
      throw const FormatException('Invalid ciphertext');
    }
    final mac = Mac(blob.sublist(blob.length - 16));
    final cipherText = blob.sublist(0, blob.length - 16);
    final clear = await _aes.decrypt(
      SecretBox(
        cipherText,
        nonce: base64Decode(ciphertext.nonce),
        mac: mac,
      ),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  static Future<VaultKeySet> createKeys(String masterPassword) async {
    final salt = Uint8List.fromList(newSalt());
    final kek = await deriveKek(masterPassword: masterPassword, salt: salt);
    final dek = await newDek();
    final wrapped = await encryptString(
      base64Encode(await dek.extractBytes()),
      kek,
    );
    return VaultKeySet(
      dek: dek,
      salt: base64Encode(salt),
      wrappedDek: wrapped.payload,
      wrappedDekNonce: wrapped.nonce,
    );
  }

  static Future<SecretKey> unwrapDek({
    required String masterPassword,
    required String saltB64,
    required String wrappedDek,
    required String wrappedDekNonce,
    int memory = 8192,
    int iterations = 3,
    int parallelism = 1,
  }) async {
    final kek = await deriveKek(
      masterPassword: masterPassword,
      salt: base64Decode(saltB64),
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
    final encoded = await decryptString(
      VaultCiphertext(nonce: wrappedDekNonce, payload: wrappedDek),
      kek,
    );
    return SecretKey(base64Decode(encoded));
  }
}
