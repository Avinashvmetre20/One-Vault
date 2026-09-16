import 'dart:async';

import 'package:flutter/material.dart';

import '../features/authentication/data/auth_models.dart';
import '../features/authentication/data/auth_service.dart';
import '../features/authentication/data/auth_storage.dart';
import '../shared/enums/enums.dart';
import '../shared/models/models.dart';

class AppState extends ChangeNotifier {
  AppState({
    this.restoreOnStart = true,
    AuthService? authService,
    AuthStorage? authStorage,
  }) : _injectedAuthService = authService,
       _injectedAuthStorage = authStorage {
    _seed();
    if (!restoreOnStart) {
      isReady = true;
    }
  }

  factory AppState.authenticated() {
    final state = AppState(restoreOnStart: false);
    state.accessToken = 'test-access-token';
    state.refreshToken = 'test-refresh-token';
    state.sessionUser = AuthUser(
      userId: 1,
      name: state.profile.name,
      email: state.profile.email,
      phone: state.profile.phone,
    );
    return state;
  }

  final bool restoreOnStart;
  final AuthService? _injectedAuthService;
  final AuthStorage? _injectedAuthStorage;
  AuthService? _authServiceInstance;
  AuthStorage? _authStorageInstance;

  AuthService get _authService =>
      _authServiceInstance ??= _injectedAuthService ?? AuthService();
  AuthStorage get _authStorage =>
      _authStorageInstance ??= _injectedAuthStorage ?? AuthStorage();

  int _nextId = 100;
  bool isReady = false;
  String? accessToken;
  String? refreshToken;
  AuthUser? sessionUser;
  ThemeMode themeMode = ThemeMode.system;
  SecuritySettings security = SecuritySettings();
  late PersonalInfo profile;

  bool get isLoggedIn =>
      accessToken != null &&
      accessToken!.isNotEmpty &&
      sessionUser != null;

  final List<PasswordItem> passwords = [];
  final List<DocumentItem> documents = [];
  final List<PhotoItem> photos = [];
  final List<FileItem> files = [];
  final List<AccountItem> accounts = [];
  final List<TransactionItem> transactions = [];
  final List<TodoItem> todos = [];
  final List<NoteItem> notes = [];
  final List<ReminderItem> reminders = [];

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

  List<TodoItem> get todaysTasks {
    final now = DateTime.now();
    return todos.where((item) {
      if (item.completed || item.dueDate == null) return false;
      return _sameDay(item.dueDate!, now);
    }).toList();
  }

  bool _isThisMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
  }

  void updateSecurity(SecuritySettings value) {
    security = value;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    try {
      final saved = await _authStorage.read();
      if (saved != null) {
        accessToken = saved.tokens.accessToken;
        refreshToken = saved.tokens.refreshToken;
        if (saved.user != null) {
          _applyUser(saved.user!);
        }
      }
    } catch (_) {
      await clearSession(notify: false);
    } finally {
      isReady = true;
      notifyListeners();
    }

    if (accessToken != null && accessToken!.isNotEmpty) {
      unawaited(_refreshSessionInBackground());
    }
  }

  Future<void> _refreshSessionInBackground() async {
    try {
      await _loadCurrentUser();
      notifyListeners();
    } on AuthException catch (error) {
      if (error.statusCode == 401) {
        await clearSession();
      }
    } catch (_) {}
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
    accessToken = null;
    refreshToken = null;
    sessionUser = null;
    await _authStorage.clear();
    if (notify) notifyListeners();
  }

  Future<void> _setSession(AuthResult result) async {
    accessToken = result.tokens.accessToken;
    refreshToken = result.tokens.refreshToken;
    _applyUser(result.user);
    await _authStorage.save(result.tokens, user: result.user);
    notifyListeners();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _authService.me(accessToken!);
      _applyUser(user);
      await _authStorage.save(
        AuthTokens(accessToken: accessToken!, refreshToken: refreshToken!),
        user: user,
      );
      return;
    } on AuthException catch (error) {
      if (error.statusCode != 401 || refreshToken == null) rethrow;
    }

    final tokens = await _authService.refresh(refreshToken!);
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
    final user = await _authService.me(accessToken!);
    _applyUser(user);
    await _authStorage.save(tokens, user: user);
  }

  void _applyUser(AuthUser user) {
    sessionUser = user;
    profile = profile.copyWith(
      name: user.name,
      email: user.email,
      phone: user.phone ?? profile.phone,
    );
  }

  void addPassword(PasswordItem item) {
    passwords.insert(0, item);
    notifyListeners();
  }

  void updatePassword(PasswordItem item) {
    final index = passwords.indexWhere((entry) => entry.id == item.id);
    if (index == -1) return;
    passwords[index] = item;
    notifyListeners();
  }

  void deletePassword(String id) {
    passwords.removeWhere((item) => item.id == id);
    notifyListeners();
  }

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

  void addTodo(TodoItem item) {
    todos.insert(0, item);
    notifyListeners();
  }

  void toggleTodo(String id) {
    final index = todos.indexWhere((item) => item.id == id);
    if (index == -1) return;
    todos[index] = todos[index].copyWith(completed: !todos[index].completed);
    notifyListeners();
  }

  void addNote(NoteItem item) {
    notes.insert(0, item);
    notifyListeners();
  }

  void addReminder(ReminderItem item) {
    reminders.insert(0, item);
    notifyListeners();
  }

  void toggleReminder(String id) {
    final index = reminders.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final current = reminders[index];
    reminders[index] = ReminderItem(
      id: current.id,
      title: current.title,
      dateTime: current.dateTime,
      recurrence: current.recurrence,
      linkedTo: current.linkedTo,
      completed: !current.completed,
    );
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

    passwords.addAll([
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
    ]);

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

    final today = DateTime.now();
    todos.addAll([
      TodoItem(
        id: 'todo-1',
        title: 'Pay electricity bill',
        description: 'MSEDCL bill due today',
        priority: TodoPriority.high,
        category: 'Bills',
        dueDate: DateTime(today.year, today.month, today.day, 18),
      ),
      TodoItem(
        id: 'todo-2',
        title: 'Submit timesheet',
        description: 'Weekly hours for payroll',
        priority: TodoPriority.medium,
        category: 'Work',
        dueDate: DateTime(today.year, today.month, today.day, 17),
      ),
      TodoItem(
        id: 'todo-3',
        title: 'Renew car insurance',
        description: 'Policy ends 12 December',
        priority: TodoPriority.high,
        category: 'Vehicle',
        dueDate: DateTime(2026, 12, 1),
      ),
      TodoItem(
        id: 'todo-4',
        title: 'Call mom',
        description: 'Sunday catch-up',
        priority: TodoPriority.low,
        category: 'Personal',
        dueDate: DateTime(today.year, today.month, today.day + 1),
      ),
    ]);

    notes.addAll([
      NoteItem(
        id: 'note-1',
        title: 'HDFC locker',
        content: 'Locker number 214. Visit branch before 4 PM on weekdays.',
        tags: const ['hdfc', 'bank'],
        updatedAt: DateTime(2026, 9, 14),
        isPinned: true,
      ),
      NoteItem(
        id: 'note-2',
        title: 'Gift ideas',
        content: 'Wireless earbuds, notebook set, dinner reservation.',
        tags: const ['personal'],
        updatedAt: DateTime(2026, 9, 10),
      ),
      NoteItem(
        id: 'note-3',
        title: 'Sprint notes',
        content: 'Ship vault list screens, then wire Express APIs.',
        tags: const ['work'],
        updatedAt: DateTime(2026, 9, 16),
        isFavorite: true,
      ),
    ]);

    reminders.addAll([
      ReminderItem(
        id: 'rem-1',
        title: 'Car insurance expiry',
        dateTime: DateTime(2026, 12, 12, 9),
        recurrence: ReminderRecurrence.none,
        linkedTo: 'Car Insurance.pdf',
      ),
      ReminderItem(
        id: 'rem-2',
        title: 'Credit card due',
        dateTime: DateTime(2026, 9, 22, 10),
        recurrence: ReminderRecurrence.monthly,
        linkedTo: 'HDFC Credit Card',
      ),
      ReminderItem(
        id: 'rem-3',
        title: 'SIP instalment',
        dateTime: DateTime(2026, 9, 20, 8),
        recurrence: ReminderRecurrence.monthly,
        linkedTo: 'Investments',
      ),
    ]);
  }
}
