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
  bool _remoteSynced = false;
  Future<void>? _syncing;

  bool get isUnlocked => memoryOnly ? _memoryUnlocked : _unlocked;
  bool get isSetup => true;

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
    final cached = await _store.readPasswords(userId);
    _replace(cached);
    _unlocked = true;
    _hydrated = true;
    _notify();
  }

  void unlockDemo(List<PasswordItem> items) {
    _memoryUnlocked = true;
    _replace(items);
    _notify();
  }

  Future<void> setup(String masterPassword) async {
    await unlock();
  }

  Future<void> unlockWithPassword(String masterPassword) async {
    await unlock();
  }

  Future<void> unlock() async {
    unlocking = true;
    _notify();
    try {
      await sync();
      _unlocked = true;
      await _importAutofillSaves();
      await _syncAutofillCache();
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
    if (clearUser) {
      _hydrated = false;
      _remoteSynced = false;
      await AutofillBridge.clearCredentials();
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
    await _writeLocal();
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
    _plain.remove(id);
    if (!memoryOnly) {
      try {
        await _api.delete(id);
      } on VaultApiException catch (error) {
        _plain[id] = item;
        throw VaultException(error.message);
      }
      await _writeLocal();
      await _syncAutofillCache();
    }
    _notify();
  }

  Future<void> ensureRemoteSync() {
    if (memoryOnly || _remoteSynced) return Future.value();
    return sync();
  }

  Future<void> sync() async {
    if (memoryOnly || _token() == null || _token() == 'test-access-token') return;
    final inFlight = _syncing;
    if (inFlight != null) return inFlight;
    final future = _syncRemote();
    _syncing = future;
    try {
      await future;
    } finally {
      if (identical(_syncing, future)) _syncing = null;
    }
  }

  Future<void> _syncRemote() async {
    try {
      final remote = await _api.list();
      _replace(remote);
      await _writeLocal();
      _remoteSynced = true;
    } catch (_) {
      if (_plain.isEmpty) {
        final userId = _userId();
        if (userId != null) {
          _replace(await _store.readPasswords(userId));
        }
      }
    }
  }

  Future<void> _writeLocal() async {
    final userId = _userId();
    if (userId == null || memoryOnly) return;
    await _store.writePasswords(userId, _plain.values.toList());
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

  Future<void> _syncAutofillCache() async {
    if (memoryOnly || !isUnlocked) return;
    await AutofillBridge.syncCredentials(credentials);
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
