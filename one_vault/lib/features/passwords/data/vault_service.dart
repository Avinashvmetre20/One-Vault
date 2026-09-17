import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/enums/enums.dart';
import '../../../shared/models/models.dart';
import 'autofill_bridge.dart';
import 'vault_api.dart';
import 'vault_crypto.dart';
import 'vault_models.dart';
import 'vault_storage.dart';
import 'vault_urls.dart';

class VaultException implements Exception {
  const VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VaultService extends ChangeNotifier {
  VaultService({
    required String? Function() token,
    required int? Function() userId,
    this.memoryOnly = false,
    VoidCallback? onChanged,
    VaultLocalStore? store,
    VaultApi? api,
    LocalAuthentication? localAuth,
  }) : _token = token,
       _userId = userId,
       _onChanged = onChanged,
       _store = store ?? VaultLocalStore(),
       _api = api ?? VaultApi(token: token),
       _localAuth = localAuth ?? LocalAuthentication();

  final String? Function() _token;
  final int? Function() _userId;
  final bool memoryOnly;
  final VoidCallback? _onChanged;
  final VaultLocalStore _store;
  final VaultApi _api;
  final LocalAuthentication _localAuth;
  final _uuid = const Uuid();

  SecretKey? _dek;
  VaultSnapshot _snapshot = const VaultSnapshot();
  final Map<String, PasswordItem> _plain = {};
  DateTime? _backgroundedAt;
  VaultAutoLock autoLock = VaultAutoLock.oneMinute;
  bool biometricEnabled = false;
  bool unlocking = false;
  bool _memoryUnlocked = false;

  bool get isUnlocked => _dek != null || _memoryUnlocked;
  bool get isSetup => memoryOnly || _snapshot.meta != null;
  bool get hasBiometricKey => biometricEnabled && !memoryOnly;

  List<PasswordItem> get credentials {
    if (!isUnlocked) return const [];
    final items = _plain.values.where((item) => item.deletedAt == null).toList()
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return items;
  }

  PasswordItem? byId(String id) {
    if (!isUnlocked) return null;
    final item = _plain[id];
    if (item == null || item.deletedAt != null) return null;
    return item;
  }

  Future<void> bind() async {
    if (memoryOnly) return;
    final userId = _userId();
    if (userId == null) return;
    _snapshot = await _store.readSnapshot(userId);
    if (_snapshot.meta == null) {
      try {
        final remote = await _api.meta();
        if (remote != null) {
          _snapshot = VaultSnapshot(
            meta: remote,
            credentials: _snapshot.credentials,
          );
          await _writeLocal();
        }
      } catch (_) {}
    }
    autoLock = await _store.autoLock(userId);
    biometricEnabled = await _store.biometricEnabled(userId);
    _notify();
  }

  void unlockDemo(List<PasswordItem> items) {
    _memoryUnlocked = true;
    _plain
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
    _notify();
  }

  Future<void> setup(String masterPassword) async {
    if (masterPassword.trim().length < 6) {
      throw const VaultException('Vault password must be at least 6 characters');
    }
    final keys = await VaultCrypto.createKeys(masterPassword.trim());
    _dek = keys.dek;
    _snapshot = VaultSnapshot(
      meta: VaultMeta(
        salt: keys.salt,
        wrappedDek: keys.wrappedDek,
        wrappedDekNonce: keys.wrappedDekNonce,
        kdfMemory: keys.kdfMemory,
        kdfIterations: keys.kdfIterations,
        kdfParallelism: keys.kdfParallelism,
      ),
      credentials: const [],
    );
    _plain.clear();
    await _persistMeta();
    await _persistDekIfAllowed();
    await _importAutofillSaves();
    await _syncAutofillCache();
    _notify();
  }

  Future<void> unlockWithPassword(String masterPassword) async {
    unlocking = true;
    _notify();
    try {
      await _ensureMeta();
      final meta = _snapshot.meta;
      if (meta == null) {
        throw const VaultException('Vault is not set up yet');
      }
      _dek = await VaultCrypto.unwrapDek(
        masterPassword: masterPassword.trim(),
        saltB64: meta.salt,
        wrappedDek: meta.wrappedDek,
        wrappedDekNonce: meta.wrappedDekNonce,
        memory: meta.kdfMemory,
        iterations: meta.kdfIterations,
        parallelism: meta.kdfParallelism,
      );
      await _decryptAll();
      await _persistDekIfAllowed();
      await sync();
      await _importAutofillSaves();
      await _syncAutofillCache();
    } on VaultException {
      rethrow;
    } catch (_) {
      _dek = null;
      _plain.clear();
      throw const VaultException('Could not unlock vault. Check your vault password.');
    } finally {
      unlocking = false;
      _notify();
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (memoryOnly) return false;
    final userId = _userId();
    if (userId == null || !biometricEnabled) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock your OneVault passwords',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return false;
      final bytes = await _store.readDek(userId);
      if (bytes == null) return false;
      _dek = SecretKey(bytes);
      await _ensureMeta();
      await _decryptAll();
      await sync();
      await _importAutofillSaves();
      await _syncAutofillCache();
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> lock({bool clearUser = false}) async {
    if (memoryOnly && !clearUser) return;
    _dek = null;
    _plain.clear();
    _backgroundedAt = null;
    _memoryUnlocked = false;
    if (clearUser) {
      _snapshot = const VaultSnapshot();
      await AutofillBridge.clearCredentials();
    }
    _notify();
  }

  Future<void> setBiometricEnabled(bool value) async {
    final userId = _userId();
    if (userId == null || memoryOnly) return;
    biometricEnabled = value;
    await _store.setBiometricEnabled(userId, value);
    if (value) {
      await _persistDekIfAllowed();
    } else {
      await _store.clearDek(userId);
    }
    _notify();
  }

  Future<void> setAutoLock(VaultAutoLock value) async {
    final userId = _userId();
    autoLock = value;
    if (userId != null && !memoryOnly) {
      await _store.setAutoLock(userId, value);
    }
    _notify();
  }

  void onBackgrounded() {
    if (!isUnlocked || memoryOnly) return;
    if (autoLock == VaultAutoLock.immediately) {
      _dek = null;
      _plain.clear();
      _notify();
      return;
    }
    _backgroundedAt = DateTime.now();
  }

  void onResumed() {
    if (memoryOnly || _backgroundedAt == null || _dek == null) return;
    final limit = autoLock.duration;
    if (limit == null) return;
    if (DateTime.now().difference(_backgroundedAt!) >= limit) {
      _dek = null;
      _plain.clear();
    }
    _backgroundedAt = null;
    _notify();
  }

  String newId() => _uuid.v4();

  Future<void> upsert(PasswordItem item) async {
    _assertUnlocked();
    final now = DateTime.now();
    final stored = item.copyWith(
      updatedAt: now,
      version: _plain.containsKey(item.id) ? item.version + 1 : item.version,
    );
    _plain[stored.id] = stored;
    await _persistCredential(stored);
    await _syncAutofillCache();
    _notify();
  }

  Future<void> toggleFavorite(String id) async {
    final item = byId(id);
    if (item == null) return;
    await upsert(item.copyWith(isFavorite: !item.isFavorite));
  }

  Future<void> delete(String id) async {
    final item = byId(id);
    if (item == null) return;
    final deleted = item.copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      version: item.version + 1,
    );
    _plain.remove(id);
    await _persistCredential(deleted);
    await _syncAutofillCache();
    _notify();
  }

  Future<void> sync() async {
    if (memoryOnly || _token() == null || _token() == 'test-access-token') return;
    try {
      await _pushMeta();
      final remote = await _api.credentials(includeDeleted: true);
      final localById = {
        for (final item in _snapshot.credentials) item.id: item,
      };
      var changed = false;
      for (final remoteItem in remote) {
        final local = localById[remoteItem.id];
        if (local == null || remoteItem.version > local.version) {
          localById[remoteItem.id] = remoteItem;
          changed = true;
        } else if (local.version > remoteItem.version) {
          await _api.upsert(local);
        }
      }
      for (final local in _snapshot.credentials) {
        if (!remote.any((item) => item.id == local.id)) {
          await _api.upsert(local);
        }
      }
      if (changed) {
        _snapshot = VaultSnapshot(
          meta: _snapshot.meta,
          credentials: localById.values.toList(),
        );
        await _writeLocal();
        if (_dek != null) {
          await _decryptAll();
          await _syncAutofillCache();
        }
      }
    } catch (_) {
      // Offline access continues from the local encrypted cache.
    }
  }

  Future<void> _ensureMeta() async {
    if (_snapshot.meta != null) return;
    try {
      final remote = await _api.meta();
      if (remote != null) {
        _snapshot = VaultSnapshot(meta: remote, credentials: _snapshot.credentials);
        await _writeLocal();
      }
    } catch (_) {}
  }

  Future<void> _decryptAll() async {
    final dek = _dek;
    if (dek == null) return;
    _plain.clear();
    for (final encrypted in _snapshot.credentials) {
      if (encrypted.deletedAt != null) continue;
      try {
        final payload = await VaultCrypto.decryptString(
          VaultCiphertext(nonce: encrypted.nonce, payload: encrypted.encryptedPayload),
          dek,
        );
        final item = PasswordItem.fromPayload(
          jsonDecode(payload) as Map<String, dynamic>,
        );
        _plain[item.id] = item.copyWith(version: encrypted.version);
      } catch (_) {
        // Skip records that cannot be decrypted with this key.
      }
    }
  }

  Future<void> _persistCredential(PasswordItem item) async {
    if (memoryOnly) return;
    final dek = _dek;
    if (dek == null) return;
    final cipher = await VaultCrypto.encryptString(
      jsonEncode(item.toPayload()),
      dek,
    );
    final encrypted = EncryptedCredential(
      id: item.id,
      nonce: cipher.nonce,
      encryptedPayload: cipher.payload,
      version: item.version,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      deletedAt: item.deletedAt,
    );
    final next = [
      ..._snapshot.credentials.where((entry) => entry.id != item.id),
      encrypted,
    ];
    _snapshot = VaultSnapshot(meta: _snapshot.meta, credentials: next);
    await _writeLocal();
    try {
      await _api.upsert(encrypted);
    } catch (_) {}
  }

  Future<void> _persistMeta() async {
    await _writeLocal();
    await _pushMeta();
  }

  Future<void> _pushMeta() async {
    final meta = _snapshot.meta;
    if (meta == null || memoryOnly) return;
    try {
      await _api.putMeta(meta);
    } catch (_) {}
  }

  Future<void> _writeLocal() async {
    final userId = _userId();
    if (userId == null || memoryOnly) return;
    await _store.writeSnapshot(userId, _snapshot);
  }

  Future<void> _persistDekIfAllowed() async {
    final userId = _userId();
    final dek = _dek;
    if (userId == null || dek == null || memoryOnly || !biometricEnabled) return;
    await _store.saveDek(userId, await dek.extractBytes());
  }

  Future<void> _importAutofillSaves() async {
    if (memoryOnly || !isUnlocked) return;
    final pending = await AutofillBridge.pendingSaves();
    for (final raw in pending) {
      final id = raw['id'] ?? '';
      final username = raw['username'] ?? '';
      final password = raw['password'] ?? '';
      if (id.isEmpty || password.isEmpty) continue;
      final domain = (raw['domain'] ?? '').toLowerCase();
      final website = (raw['website'] ?? '').isNotEmpty
          ? raw['website']!
          : (domain.isEmpty ? '' : VaultUrls.normalize(domain));
      final title = (raw['title'] ?? '').isNotEmpty
          ? raw['title']!
          : (domain.isEmpty ? 'Login' : domain);

      PasswordItem? existing = byId(id);
      if (existing == null && username.isNotEmpty && domain.isNotEmpty) {
        for (final item in credentials) {
          if (item.username.toLowerCase() == username.toLowerCase() &&
              (item.domain == domain || item.website.toLowerCase().contains(domain))) {
            existing = item;
            break;
          }
        }
      }
      if (existing != null) {
        if (existing.password == password && existing.username == username) continue;
        await upsert(
          existing.copyWith(
            password: password,
            username: username.isEmpty ? existing.username : username,
            website: website.isEmpty ? existing.website : website,
            domain: domain.isEmpty ? existing.domain : domain,
          ),
        );
      } else {
        await upsert(
          PasswordItem(
            id: id,
            title: title,
            username: username,
            password: password,
            website: website,
            category: PasswordCategory.other,
            notes: '',
            tags: const [],
            updatedAt: DateTime.now(),
            domain: domain,
          ),
        );
      }
    }
  }

  Future<void> _syncAutofillCache() async {
    if (memoryOnly || !isUnlocked) return;
    await AutofillBridge.syncCredentials(credentials);
  }

  void _assertUnlocked() {
    if (!isUnlocked) {
      throw const VaultException('Unlock the vault first');
    }
  }

  void _notify() {
    notifyListeners();
    _onChanged?.call();
  }
}
