import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../core/network/api_client.dart';
import '../features/authentication/data/auth_models.dart';
import '../features/authentication/data/auth_service.dart';
import '../features/authentication/data/auth_storage.dart';
import '../features/authentication/data/mpin_storage.dart';
import '../features/passwords/data/vault_api.dart';
import '../features/passwords/data/vault_service.dart';
import '../features/planner/data/planner_service.dart';
import '../features/settings/data/theme_storage.dart';
import '../shared/enums/enums.dart';
import '../shared/models/models.dart';

class AppState extends ChangeNotifier {
  AppState({
    this.restoreOnStart = true,
    this.demoVault = false,
    AuthService? authService,
    AuthStorage? authStorage,
    MpinStorage? mpinStorage,
  }) : _injectedAuthService = authService,
       _injectedAuthStorage = authStorage,
       _mpinStorage = mpinStorage ?? MpinStorage() {
    _apiClient = ApiClient(refreshAccessToken: _refreshAccessToken);
    vault = VaultService(
      token: () => accessToken,
      userId: () => sessionUser?.userId,
      memoryOnly: demoVault,
      onChanged: notifyListeners,
      api: VaultApi(token: () => accessToken, apiClient: _apiClient),
    );
    planner = PlannerService(
      token: () => accessToken,
      onChanged: notifyPlannerChanged,
      apiClient: _apiClient,
    );
    _seed();
    if (demoVault) {
      vault.unlockDemo(_demoPasswords());
    }
    if (!restoreOnStart) {
      isReady = true;
    }
  }

  factory AppState.authenticated() {
    final state = AppState(restoreOnStart: false, demoVault: true);
    state.accessToken = 'test-access-token';
    state.refreshToken = 'test-refresh-token';
    state.sessionUser = AuthUser(
      userId: 1,
      name: state.profile.name,
      email: state.profile.email,
      phone: state.profile.phone,
    );
    state.hasMpin = true;
    state.mpinUnlocked = true;
    return state;
  }

  final bool restoreOnStart;
  final bool demoVault;
  final AuthService? _injectedAuthService;
  final AuthStorage? _injectedAuthStorage;
  final MpinStorage _mpinStorage;
  final LocalAuthentication _localAuth = LocalAuthentication();
  AuthService? _authServiceInstance;
  AuthStorage? _authStorageInstance;
  final ThemeStorage _themeStorage = ThemeStorage();

  AuthService get _authService =>
      _authServiceInstance ??=
          _injectedAuthService ?? AuthService(apiClient: _apiClient);
  AuthStorage get _authStorage =>
      _authStorageInstance ??= _injectedAuthStorage ?? AuthStorage();
  late final ApiClient _apiClient;
  Completer<bool>? _refreshLock;

  int _nextId = 100;
  bool isReady = false;
  String? accessToken;
  String? refreshToken;
  AuthUser? sessionUser;
  ThemeMode themeMode = ThemeMode.system;
  SecuritySettings security = SecuritySettings();
  late PersonalInfo profile;
  bool hasMpin = false;
  bool mpinUnlocked = false;
  int mpinAttemptsLeft = MpinStorage.maxAttempts;
  bool biometricUnlockEnabled = false;
  bool biometricAvailable = false;
  bool _biometricPromptOpen = false;
  String? authNotice;

  late final VaultService vault;

  bool get isLoggedIn =>
      accessToken != null &&
      accessToken!.isNotEmpty &&
      sessionUser != null;

  bool get needsMpinSetup => isLoggedIn && !hasMpin;
  bool get needsMpinUnlock => isLoggedIn && hasMpin && !mpinUnlocked;
  bool get isAppUnlocked => isLoggedIn && mpinUnlocked;

  List<PasswordItem> get passwords => vault.credentials;
  final List<DocumentItem> documents = [];
  final List<PhotoItem> photos = [];
  final List<FileItem> files = [];
  final List<AccountItem> accounts = [];
  final List<TransactionItem> transactions = [];

  late final PlannerService planner;

  final ValueNotifier<int> plannerTick = ValueNotifier<int>(0);
  final ValueNotifier<int> shellTabIndex = ValueNotifier<int>(0);

  void notifyPlannerChanged() {
    plannerTick.value++;
  }

  String nextId(String prefix) => '$prefix-${_nextId++}';

  double get monthlyIncome => transactions
      .where((item) => item.type == TransactionType.income && _isThisMonth(item.date))
      .fold(0, (sum, item) => sum + item.amount);

  double get monthlyExpense => transactions
      .where((item) => item.type == TransactionType.expense && _isThisMonth(item.date))
      .fold(0, (sum, item) => sum + item.amount);

  double get currentBalance =>
      accounts.fold(0, (sum, item) => sum + item.balance);

  double get monthlySavings => monthlyIncome - monthlyExpense;

  bool _isThisMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  AccountItem? accountById(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    unawaited(_themeStorage.write(mode));
  }

  void updateSecurity(SecuritySettings value) {
    security = value;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    final themeFuture = _themeStorage.read();
    SavedSession? saved;
    try {
      saved = await _authStorage.read();
    } catch (_) {
      await clearSession(notify: false);
    }
    themeMode = await themeFuture;

    if (saved != null) {
      accessToken = saved.tokens.accessToken;
      refreshToken = saved.tokens.refreshToken;
      if (saved.user != null) {
        _applyUser(saved.user!);
      }
    }

    await _loadMpinState(unlockIfPresent: false);
    isReady = true;
    notifyListeners();
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final result = await _authService.login(email: email, password: password);
    await _setSession(result);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final result = await _authService.register(
      name: name,
      email: email,
      password: password,
      phone: phone,
    );
    await _setSession(result);
  }

  Future<void> logout() async {
    final token = refreshToken;
    if (token != null) {
      try {
        await _authService.logout(token);
      } catch (_) {}
    }
    await clearSession();
  }

  Future<void> clearSession({bool notify = true}) async {
    final userId = sessionUser?.userId;
    accessToken = null;
    refreshToken = null;
    sessionUser = null;
    hasMpin = false;
    mpinUnlocked = false;
    mpinAttemptsLeft = MpinStorage.maxAttempts;
    biometricUnlockEnabled = false;
    shellTabIndex.value = 0;
    if (userId != null) {
      await _mpinStorage.clear(userId);
    }
    await _authStorage.clear();
    await vault.lock(clearUser: true);
    if (notify) notifyListeners();
  }

  Future<void> _setSession(AuthResult result) async {
    accessToken = result.tokens.accessToken;
    refreshToken = result.tokens.refreshToken;
    _applyUser(result.user);
    await _authStorage.save(result.tokens, user: result.user);
    await _loadMpinState(unlockIfPresent: true);
    await _bindVaultIfUnlocked();
    notifyListeners();
  }

  Future<void> _bindVaultIfUnlocked() async {
    if (!isAppUnlocked || demoVault) return;
    await vault.bind();
  }

  String? takeAuthNotice() {
    final notice = authNotice;
    authNotice = null;
    return notice;
  }

  Future<void> _loadMpinState({required bool unlockIfPresent}) async {
    final userId = sessionUser?.userId;
    if (userId == null) {
      hasMpin = false;
      mpinUnlocked = false;
      mpinAttemptsLeft = MpinStorage.maxAttempts;
      biometricUnlockEnabled = false;
      return;
    }

    final mpin = await Future.wait([
      _mpinStorage.hasPin(userId),
      _mpinStorage.biometricEnabled(userId),
      _mpinStorage.attempts(userId),
    ]);
    hasMpin = mpin[0] as bool;
    biometricUnlockEnabled = mpin[1] as bool;
    final used = mpin[2] as int;
    mpinAttemptsLeft = (MpinStorage.maxAttempts - used).clamp(0, MpinStorage.maxAttempts);
    if (hasMpin && unlockIfPresent) {
      mpinUnlocked = true;
      mpinAttemptsLeft = MpinStorage.maxAttempts;
      await _mpinStorage.resetAttempts(userId);
    } else {
      mpinUnlocked = false;
    }
  }

  Future<void> setupMpin(String pin, {bool enableBiometric = false}) async {
    final userId = sessionUser?.userId;
    if (userId == null) {
      throw const MpinException('Sign in first');
    }
    if (!_mpinStorage.isValidPin(pin)) {
      throw const MpinException('MPIN must be 4 digits');
    }
    await _mpinStorage.save(userId, pin);
    if (enableBiometric) {
      await _mpinStorage.setBiometricEnabled(userId, true);
      biometricUnlockEnabled = true;
    } else {
      biometricUnlockEnabled = await _mpinStorage.biometricEnabled(userId);
    }
    hasMpin = true;
    mpinUnlocked = true;
    mpinAttemptsLeft = MpinStorage.maxAttempts;
    await _bindVaultIfUnlocked();
    notifyListeners();
  }

  Future<bool> unlockMpin(String pin) async {
    final userId = sessionUser?.userId;
    if (userId == null) return false;
    if (!_mpinStorage.isValidPin(pin)) return false;

    final ok = await _mpinStorage.verify(userId, pin);
    if (ok) {
      mpinUnlocked = true;
      mpinAttemptsLeft = MpinStorage.maxAttempts;
      await _mpinStorage.resetAttempts(userId);
      await _bindVaultIfUnlocked();
      notifyListeners();
      return true;
    }

    final used = await _mpinStorage.incrementAttempts(userId);
    mpinAttemptsLeft = (MpinStorage.maxAttempts - used).clamp(0, MpinStorage.maxAttempts);
    if (used >= MpinStorage.maxAttempts) {
      authNotice = 'Too many incorrect MPIN attempts. Sign in with email and password.';
      await _mpinStorage.resetAttempts(userId);
      await logout();
      return false;
    }
    notifyListeners();
    return false;
  }

  Future<bool> canUseAppBiometric() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshBiometricAvailable() async {
    biometricAvailable = await canUseAppBiometric();
  }

  Future<void> refreshBiometricAvailable() async {
    await _refreshBiometricAvailable();
    notifyListeners();
  }

  Future<bool> promptAppBiometric(String reason) async {
    _biometricPromptOpen = true;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    } finally {
      _biometricPromptOpen = false;
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (!hasMpin || !biometricUnlockEnabled) return false;
    final ok = await promptAppBiometric('Unlock OneVault');
    if (!ok) return false;
    mpinUnlocked = true;
    mpinAttemptsLeft = MpinStorage.maxAttempts;
    final userId = sessionUser?.userId;
    if (userId != null) await _mpinStorage.resetAttempts(userId);
    await _bindVaultIfUnlocked();
    notifyListeners();
    return true;
  }

  Future<void> setAppBiometricEnabled(bool value, {bool verify = true}) async {
    final userId = sessionUser?.userId;
    if (userId == null) {
      throw const MpinException('Sign in first');
    }
    if (value && verify) {
      if (!await canUseAppBiometric()) {
        throw const MpinException(
          'Turn on fingerprint in phone settings first',
        );
      }
      final ok = await promptAppBiometric(
        'Confirm your fingerprint to enable app unlock',
      );
      if (!ok) {
        throw const MpinException('Fingerprint not verified');
      }
    }
    await _mpinStorage.setBiometricEnabled(userId, value);
    biometricUnlockEnabled = value;
    notifyListeners();
  }

  Future<void> changeMpin({
    required String currentPin,
    required String nextPin,
  }) async {
    final userId = sessionUser?.userId;
    if (userId == null) {
      throw const MpinException('Sign in first');
    }
    if (!_mpinStorage.isValidPin(nextPin)) {
      throw const MpinException('MPIN must be 4 digits');
    }
    final ok = await _mpinStorage.verify(userId, currentPin);
    if (!ok) {
      throw const MpinException('Current MPIN is incorrect');
    }
    await _mpinStorage.save(userId, nextPin);
    hasMpin = true;
    mpinUnlocked = true;
    mpinAttemptsLeft = MpinStorage.maxAttempts;
    notifyListeners();
  }

  void lockMpin() {
    if (!restoreOnStart || demoVault || _biometricPromptOpen) return;
    if (!isLoggedIn || !hasMpin || !mpinUnlocked) return;
    mpinUnlocked = false;
    notifyListeners();
  }

  Future<bool> _refreshAccessToken() async {
    if (demoVault) return false;
    final pending = _refreshLock;
    if (pending != null) return pending.future;

    final token = refreshToken;
    if (token == null || token.isEmpty || token == 'test-refresh-token') {
      return false;
    }

    final lock = Completer<bool>();
    _refreshLock = lock;
    try {
      final tokens = await _authService.refresh(token);
      accessToken = tokens.accessToken;
      refreshToken = tokens.refreshToken;
      await _authStorage.save(tokens, user: sessionUser);
      lock.complete(true);
      return true;
    } catch (_) {
      lock.complete(false);
      return false;
    } finally {
      _refreshLock = null;
    }
  }

  void _applyUser(AuthUser user) {
    sessionUser = user;
    profile = profile.copyWith(
      name: user.name,
      email: user.email,
      phone: user.phone ?? profile.phone,
    );
  }

  Future<void> addPassword(PasswordItem item) => vault.upsert(item);

  Future<void> updatePassword(PasswordItem item) => vault.upsert(item);

  Future<void> deletePassword(String id) => vault.delete(id);

  Future<void> togglePasswordFavorite(String id) => vault.toggleFavorite(id);

  void addDocument(DocumentItem item) {
    documents.insert(0, item);
    notifyListeners();
  }

  void addPhoto(PhotoItem item) {
    photos.insert(0, item);
    notifyListeners();
  }

  void addFile(FileItem item) {
    files.insert(0, item);
    notifyListeners();
  }

  void addTransaction(TransactionItem item) {
    transactions.insert(0, item);
    notifyListeners();
  }

  void _seed() {
    profile = PersonalInfo(
      name: 'Avinash',
      dateOfBirth: DateTime(1996, 4, 18),
      phone: '+91 98765 43210',
      email: 'avinash@example.com',
      address: 'Pune, Maharashtra',
      emergencyContact: 'Priya — +91 98765 11111',
      bloodGroup: 'B+',
      nationality: 'Indian',
      pan: 'ABCDE1234F',
      aadhaar: '123412341234',
      passport: 'N1234567',
      drivingLicense: 'MH12 20210012345',
      company: 'OneVault Labs',
      employeeId: 'OV-204',
      designation: 'Product Engineer',
    );

    documents.addAll([
      DocumentItem(
        id: 'doc-1',
        name: 'Aadhaar Card.pdf',
        category: DocumentCategory.identity,
        fileType: 'PDF',
        sizeLabel: '1.2 MB',
        createdAt: DateTime(2025, 11, 2),
        tags: const ['id', 'aadhaar'],
        isFavorite: true,
      ),
      DocumentItem(
        id: 'doc-2',
        name: 'PAN Card.pdf',
        category: DocumentCategory.identity,
        fileType: 'PDF',
        sizeLabel: '420 KB',
        createdAt: DateTime(2025, 10, 18),
        tags: const ['id', 'pan'],
      ),
      DocumentItem(
        id: 'doc-3',
        name: 'Salary Slip Aug 2026.pdf',
        category: DocumentCategory.salary,
        fileType: 'PDF',
        sizeLabel: '860 KB',
        createdAt: DateTime(2026, 9, 1),
        tags: const ['salary'],
      ),
      DocumentItem(
        id: 'doc-4',
        name: 'HDFC Statement.pdf',
        category: DocumentCategory.banking,
        fileType: 'PDF',
        sizeLabel: '2.4 MB',
        createdAt: DateTime(2026, 9, 8),
        tags: const ['hdfc', 'bank'],
      ),
      DocumentItem(
        id: 'doc-5',
        name: 'Car Insurance.pdf',
        category: DocumentCategory.insurance,
        fileType: 'PDF',
        sizeLabel: '1.8 MB',
        createdAt: DateTime(2025, 12, 12),
        expiryDate: DateTime(2026, 12, 12),
        tags: const ['vehicle', 'insurance'],
        isFavorite: true,
      ),
      DocumentItem(
        id: 'doc-6',
        name: 'Passport.pdf',
        category: DocumentCategory.travel,
        fileType: 'PDF',
        sizeLabel: '3.1 MB',
        createdAt: DateTime(2024, 3, 9),
        expiryDate: DateTime(2031, 3, 9),
        tags: const ['travel'],
      ),
    ]);

    photos.addAll([
      PhotoItem(
        id: 'photo-1',
        name: 'Vehicle.jpg',
        album: 'Vehicle',
        createdAt: DateTime(2026, 8, 14),
        sizeLabel: '3.4 MB',
        isFavorite: true,
      ),
      PhotoItem(
        id: 'photo-2',
        name: 'Service.jpg',
        album: 'Vehicle',
        createdAt: DateTime(2026, 8, 14),
        sizeLabel: '2.1 MB',
      ),
      PhotoItem(
        id: 'photo-3',
        name: 'Apartment.jpg',
        album: 'Property',
        createdAt: DateTime(2026, 5, 2),
        sizeLabel: '4.8 MB',
      ),
      PhotoItem(
        id: 'photo-4',
        name: 'ID Photo.jpg',
        album: 'Personal',
        createdAt: DateTime(2026, 1, 20),
        sizeLabel: '980 KB',
        isPrivate: true,
      ),
    ]);

    files.addAll([
      FileItem(
        id: 'file-1',
        name: 'Monthly Budget.xlsx',
        folder: 'Finance',
        fileType: 'XLSX',
        sizeLabel: '186 KB',
        createdAt: DateTime(2026, 9, 2),
        isFavorite: true,
      ),
      FileItem(
        id: 'file-2',
        name: 'Resume.docx',
        folder: 'Personal',
        fileType: 'DOCX',
        sizeLabel: '94 KB',
        createdAt: DateTime(2026, 4, 11),
      ),
      FileItem(
        id: 'file-3',
        name: 'Tax_AY2026.pdf',
        folder: 'Tax',
        fileType: 'PDF',
        sizeLabel: '1.5 MB',
        createdAt: DateTime(2026, 7, 22),
      ),
      FileItem(
        id: 'file-4',
        name: 'Meeting Notes.txt',
        folder: 'Work',
        fileType: 'TXT',
        sizeLabel: '12 KB',
        createdAt: DateTime(2026, 9, 15),
      ),
    ]);

    accounts.addAll([
      AccountItem(
        id: 'acc-hdfc',
        name: 'HDFC Bank',
        type: AccountType.bank,
        balance: 35000,
      ),
      AccountItem(
        id: 'acc-sbi',
        name: 'SBI Bank',
        type: AccountType.bank,
        balance: 15000,
      ),
      AccountItem(
        id: 'acc-cash',
        name: 'Cash',
        type: AccountType.cash,
        balance: 2000,
      ),
      AccountItem(
        id: 'acc-cc',
        name: 'HDFC Credit Card',
        type: AccountType.creditCard,
        balance: -8500,
      ),
      AccountItem(
        id: 'acc-upi',
        name: 'PhonePe UPI',
        type: AccountType.upi,
        balance: 1250,
      ),
    ]);

    transactions.addAll([
      TransactionItem(
        id: 'txn-1',
        amount: 85000,
        date: DateTime(2026, 9, 1),
        accountId: 'acc-hdfc',
        category: 'Salary',
        description: 'September salary',
        type: TransactionType.income,
        paymentMethod: 'Bank transfer',
        merchant: 'OneVault Labs',
      ),
      TransactionItem(
        id: 'txn-2',
        amount: 18000,
        date: DateTime(2026, 9, 3),
        accountId: 'acc-hdfc',
        category: 'Rent',
        description: 'House rent',
        type: TransactionType.expense,
        paymentMethod: 'UPI',
        merchant: 'Landlord',
      ),
      TransactionItem(
        id: 'txn-3',
        amount: 6500,
        date: DateTime(2026, 9, 10),
        accountId: 'acc-upi',
        category: 'Food',
        description: 'Groceries and dining',
        type: TransactionType.expense,
        paymentMethod: 'UPI',
        merchant: 'BigBasket',
      ),
      TransactionItem(
        id: 'txn-4',
        amount: 4200,
        date: DateTime(2026, 9, 8),
        accountId: 'acc-sbi',
        category: 'Bills',
        description: 'Electricity and internet',
        type: TransactionType.expense,
        paymentMethod: 'Auto-debit',
        merchant: 'Utilities',
      ),
      TransactionItem(
        id: 'txn-5',
        amount: 2499,
        date: DateTime(2026, 9, 16),
        accountId: 'acc-cc',
        category: 'Shopping',
        description: 'Amazon order',
        type: TransactionType.expense,
        paymentMethod: 'Credit card',
        merchant: 'Amazon',
      ),
      TransactionItem(
        id: 'txn-6',
        amount: 3800,
        date: DateTime(2026, 9, 12),
        accountId: 'acc-upi',
        category: 'Travel',
        description: 'Cab and metro',
        type: TransactionType.expense,
        paymentMethod: 'UPI',
        merchant: 'Uber',
      ),
      TransactionItem(
        id: 'txn-7',
        amount: 7351,
        date: DateTime(2026, 9, 5),
        accountId: 'acc-hdfc',
        category: 'EMI',
        description: 'Vehicle EMI',
        type: TransactionType.expense,
        paymentMethod: 'Auto-debit',
        merchant: 'HDFC Bank',
      ),
    ]);
  }

  List<PasswordItem> _demoPasswords() {
    return [
      PasswordItem(
        id: 'pwd-1',
        title: 'HDFC NetBanking',
        username: 'avinash.hdfc',
        password: 'Hdfc#Secure92',
        website: 'https://netbanking.hdfcbank.com',
        category: PasswordCategory.banking,
        notes: 'Primary savings account login',
        tags: const ['bank', 'hdfc'],
        updatedAt: DateTime(2026, 9, 12),
        isFavorite: true,
      ),
      PasswordItem(
        id: 'pwd-2',
        title: 'Gmail',
        username: 'avinash@gmail.com',
        password: 'Mail!2026',
        website: 'https://gmail.com',
        category: PasswordCategory.email,
        notes: '',
        tags: const ['email'],
        updatedAt: DateTime(2026, 8, 30),
      ),
      PasswordItem(
        id: 'pwd-3',
        title: 'Instagram',
        username: 'avinash.creates',
        password: 'Ig#Vault16',
        website: 'https://instagram.com',
        category: PasswordCategory.socialMedia,
        notes: '',
        tags: const ['social'],
        updatedAt: DateTime(2026, 7, 21),
      ),
      PasswordItem(
        id: 'pwd-4',
        title: 'Amazon',
        username: 'avinash@example.com',
        password: 'Shop@Prime1',
        website: 'https://amazon.in',
        category: PasswordCategory.shopping,
        notes: 'Prime membership',
        tags: const ['shopping'],
        updatedAt: DateTime(2026, 9, 4),
      ),
      PasswordItem(
        id: 'pwd-5',
        title: 'GitHub',
        username: 'avinash-dev',
        password: 'DevOps#4421',
        website: 'https://github.com',
        category: PasswordCategory.development,
        notes: 'Work repositories',
        tags: const ['dev'],
        updatedAt: DateTime(2026, 9, 1),
      ),
      PasswordItem(
        id: 'pwd-6',
        title: 'Home Wi-Fi',
        username: 'Airtel_5G',
        password: 'HomeNet@88',
        website: '',
        category: PasswordCategory.wifi,
        notes: 'Living room router',
        tags: const ['home'],
        updatedAt: DateTime(2026, 6, 11),
      ),
      PasswordItem(
        id: 'pwd-7',
        title: 'Netflix',
        username: 'avinash@example.com',
        password: 'Stream#2026',
        website: 'https://netflix.com',
        category: PasswordCategory.entertainment,
        notes: '',
        tags: const ['ott'],
        updatedAt: DateTime(2026, 9, 5),
      ),
    ];
  }
}
