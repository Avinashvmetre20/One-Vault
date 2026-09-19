import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../../../shared/enums/enums.dart';
import '../../../shared/models/models.dart';
import 'autofill_bridge.dart';
import 'vault_api.dart';
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

  final Map<String, PasswordItem> _plain = {};
  DateTime? _backgroundedAt;
  VaultAutoLock autoLock = VaultAutoLock.oneMinute;
  bool biometricEnabled = false;
  bool unlocking = false;
  bool _unlocked = false;
  bool _memoryUnlocked = false;
  bool _hydrated = false;
  bool _setup = false;
  Future<void>? _syncing;

  bool get isUnlocked => memoryOnly ? _memoryUnlocked : _unlocked;
  bool get isSetup => memoryOnly ? true : _setup;
  bool get syncing => _syncing != null;

  List<PasswordItem> get credentials {
    if (!isUnlocked) return const [];
    final items = _plain.values.toList()
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return items;
  }

  PasswordItem? byId(String id) {
    if (!isUnlocked) return null;
    return _plain[id];
  }

  Future<void> bind() async {
    if (memoryOnly || _hydrated) return;
    final userId = _userId();
    if (userId == null) return;
    autoLock = await _store.autoLock(userId);
    biometricEnabled = await _store.biometricEnabled(userId);
    await _store.clearPasswords(userId);
    await AutofillBridge.clearCredentials();
    try {
      _setup = await _api.isSetup();
    } catch (_) {
      _setup = false;
    }
    _hydrated = true;
    _notify();
  }

  void unlockDemo(List<PasswordItem> items) {
    _memoryUnlocked = true;
    _replace(items);
    _notify();
  }

  Future<void> setup(String masterPassword) async {
    final passcode = masterPassword.trim();
    if (passcode.length < 6) {
      throw const VaultException('Vault passcode must be at least 6 characters');
    }
    try {
      await _api.setup(passcode);
    } on VaultApiException catch (error) {
      if (error.statusCode == 409) {
        _setup = true;
        _notify();
        throw const VaultException('Vault already set up. Unlock with your passcode.');
      }
      throw VaultException(error.message);
    }
    _setup = true;
    await _openVault();
  }

  Future<void> unlockWithPassword(String masterPassword) async {
    final passcode = masterPassword.trim();
    if (passcode.isEmpty) {
      throw const VaultException('Enter your vault passcode');
    }
    unlocking = true;
    _notify();
    try {
      try {
        await _api.unlock(passcode);
      } on VaultApiException catch (error) {
        throw VaultException(error.message);
      }
      await _openVault();
    } finally {
      unlocking = false;
      _notify();
    }
  }

  Future<void> unlock() async {
    if (!_setup) {
      throw const VaultException('Set up the vault first');
    }
    unlocking = true;
    _notify();
    try {
      await _openVault();
    } finally {
      unlocking = false;
      _notify();
    }
  }

  Future<void> _openVault() async {
    try {
      await sync();
    } catch (_) {
      _plain.clear();
    }
    _unlocked = true;
    await _importAutofillSaves();
    _notify();
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
      await unlock();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> lock({bool clearUser = false}) async {
    if (memoryOnly && !clearUser) return;
    _unlocked = false;
    _memoryUnlocked = false;
    _backgroundedAt = null;
    _plain.clear();
    final userId = _userId();
    if (userId != null) await _store.clearPasswords(userId);
    await AutofillBridge.clearCredentials();
    if (clearUser) {
      _hydrated = false;
      _setup = false;
    }
    _notify();
  }

  Future<void> setBiometricEnabled(bool value) async {
    final userId = _userId();
    if (userId == null || memoryOnly) return;
    biometricEnabled = value;
    await _store.setBiometricEnabled(userId, value);
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
      _unlocked = false;
      _plain.clear();
      _notify();
      return;
    }
    _backgroundedAt = DateTime.now();
  }

  void onResumed() {
    if (memoryOnly || _backgroundedAt == null || !_unlocked) return;
    final limit = autoLock.duration;
    if (limit == null) return;
    if (DateTime.now().difference(_backgroundedAt!) >= limit) {
      _unlocked = false;
      _plain.clear();
    }
    _backgroundedAt = null;
    _notify();
  }

  Future<void> upsert(PasswordItem item) async {
    _assertUnlocked();
    if (memoryOnly) {
      final saved = item.copyWith(
        id: item.id.isEmpty ? 'pwd-${DateTime.now().microsecondsSinceEpoch}' : item.id,
        updatedAt: DateTime.now(),
      );
      _plain[saved.id] = saved;
      _notify();
      return;
    }
    PasswordItem saved;
    try {
      saved = _isNew(item.id) ? await _api.create(item) : await _api.update(item);
    } on VaultApiException catch (error) {
      throw VaultException(error.message);
    }
    _plain.remove(item.id);
    _plain[saved.id] = saved;
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
    _plain.remove(id);
    if (!memoryOnly) {
      try {
        await _api.delete(id);
      } on VaultApiException catch (error) {
        _plain[id] = item;
        throw VaultException(error.message);
      }
    }
    _notify();
  }

  Future<void> refreshFromServer() async {
    try {
      await sync();
    } catch (_) {}
  }

  Future<void> refreshHub() async {
    if (memoryOnly) return;
    try {
      _setup = await _api.isSetup();
      _hydrated = true;
    } catch (_) {}
    if (isUnlocked) {
      await refreshFromServer();
      return;
    }
    _notify();
  }

  Future<void> sync() async {
    if (memoryOnly || _token() == null || _token() == 'test-access-token') return;
    final inFlight = _syncing;
    if (inFlight != null) return inFlight;
    final future = _syncRemote();
    _syncing = future;
    _notify();
    try {
      await future;
    } finally {
      if (identical(_syncing, future)) _syncing = null;
      _notify();
    }
  }

  Future<void> _syncRemote() async {
    final remote = await _api.list();
    _replace(remote);
  }

  Future<void> _importAutofillSaves() async {
    if (memoryOnly || !isUnlocked) return;
    final pending = await AutofillBridge.pendingSaves();
    for (final raw in pending) {
      final username = raw['username'] ?? '';
      final password = raw['password'] ?? '';
      if (password.isEmpty) continue;
      final domain = (raw['domain'] ?? '').toLowerCase();
      final website = (raw['website'] ?? '').isNotEmpty
          ? raw['website']!
          : (domain.isEmpty ? '' : VaultUrls.normalize(domain));
      final title = (raw['title'] ?? '').isNotEmpty
          ? raw['title']!
          : (domain.isEmpty ? 'Login' : domain);

      PasswordItem? existing;
      if (username.isNotEmpty && domain.isNotEmpty) {
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
            id: '',
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

  void _replace(Iterable<PasswordItem> items) {
    _plain
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
  }

  bool _isNew(String id) => id.isEmpty || int.tryParse(id) == null;

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
