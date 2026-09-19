import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import 'finance_models.dart';

class FinanceService {
  FinanceService({
    required String? Function() token,
    void Function()? onChanged,
    ApiClient? apiClient,
    http.Client? client,
  }) : _token = token,
       _onChanged = onChanged,
       _api = apiClient ?? ApiClient(client: client);

  final String? Function() _token;
  final void Function()? _onChanged;
  final ApiClient _api;
  static const _base = '/api/v1/money';
  static const _uuid = Uuid();

  MoneyOverview? overview;
  DateTime? _overviewAt;

  bool get _offline {
    final token = _token();
    return token == null || token.isEmpty || token == 'test-access-token';
  }

  String newClientId() => _uuid.v4();

  Future<int?> lastAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('money_last_account_id');
  }

  Future<int?> lastCategoryId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('money_last_category_id');
  }

  Future<void> rememberSelection({int? accountId, int? categoryId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (accountId != null) await prefs.setInt('money_last_account_id', accountId);
    if (categoryId != null) await prefs.setInt('money_last_category_id', categoryId);
  }

  Future<MoneyOverview> loadOverview({bool force = false}) async {
    if (_offline) {
      overview = const MoneyOverview();
      return overview!;
    }
    if (!force &&
        overview != null &&
        _overviewAt != null &&
        DateTime.now().difference(_overviewAt!) < const Duration(seconds: 20)) {
      return overview!;
    }
    final json = await _send(() => _api.get('$_base/overview', headers: _headers()));
    overview = MoneyOverview.fromJson(json['data'] as Map<String, dynamic>);
    _overviewAt = DateTime.now();
    return overview!;
  }

  void invalidateOverview() {
    overview = null;
    _overviewAt = null;
  }

  Future<List<MoneyAccount>> accounts({bool includeInactive = false}) async {
    if (_offline) return const [];
    final json = await _send(
      () => _api.get(
        '$_base/accounts',
        headers: _headers(),
        query: {if (includeInactive) 'includeInactive': 'true'},
      ),
    );
    return _items(json, 'accounts', MoneyAccount.fromJson);
  }

  Future<MoneyAccount> account(int id) async {
    final json = await _send(() => _api.get('$_base/accounts/$id', headers: _headers()));
    final data = json['data'] as Map<String, dynamic>;
    final account = Map<String, dynamic>.from(data['account'] as Map);
    if (data['thisMonth'] is Map) account['thisMonth'] = data['thisMonth'];
    return MoneyAccount.fromJson(account);
  }

  Future<MoneyAccount> createAccount(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/accounts', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return MoneyAccount.fromJson(
      (json['data'] as Map<String, dynamic>)['account'] as Map<String, dynamic>,
    );
  }

  Future<MoneyAccount> updateAccount(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch('$_base/accounts/$id', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return MoneyAccount.fromJson(
      (json['data'] as Map<String, dynamic>)['account'] as Map<String, dynamic>,
    );
  }

  Future<void> archiveAccount(int id, {bool restore = false}) {
    return _mutate(
      () => _api.post(
        '$_base/accounts/$id/archive',
        headers: _headers(json: true),
        body: jsonEncode({'restore': restore}),
      ),
    );
  }

  Future<void> deleteAccount(int id) {
    return _mutate(() => _api.delete('$_base/accounts/$id', headers: _headers()));
  }

  Future<List<MoneyCard>> cards({String? type, bool includeInactive = false}) async {
    if (_offline) return const [];
    final json = await _send(
      () => _api.get(
        '$_base/cards',
        headers: _headers(),
        query: {
          if (type != null) 'type': type,
          if (includeInactive) 'includeInactive': 'true',
        },
      ),
    );
    return _items(json, 'cards', MoneyCard.fromJson);
  }

  Future<MoneyCard> card(int id) async {
    final json = await _send(() => _api.get('$_base/cards/$id', headers: _headers()));
    return MoneyCard.fromJson(
      (json['data'] as Map<String, dynamic>)['card'] as Map<String, dynamic>,
    );
  }

  Future<MoneyCard> createCard(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/cards', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return MoneyCard.fromJson(
      (json['data'] as Map<String, dynamic>)['card'] as Map<String, dynamic>,
    );
  }

  Future<MoneyCard> updateCard(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch('$_base/cards/$id', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return MoneyCard.fromJson(
      (json['data'] as Map<String, dynamic>)['card'] as Map<String, dynamic>,
    );
  }

  Future<void> archiveCard(int id, {bool restore = false}) {
    return _mutate(
      () => _api.post(
        '$_base/cards/$id/archive',
        headers: _headers(json: true),
        body: jsonEncode({'restore': restore}),
      ),
    );
  }

  Future<void> deleteCard(int id) {
    return _mutate(() => _api.delete('$_base/cards/$id', headers: _headers()));
  }

  Future<List<MoneyCategory>> categories({String? kind}) async {
    if (_offline) return const [];
    final json = await _send(
      () => _api.get(
        '$_base/categories',
        headers: _headers(),
        query: {if (kind != null) 'kind': kind},
      ),
    );
    return _items(json, 'categories', MoneyCategory.fromJson);
  }

  Future<MoneyCategory> createCategory(String name, String kind) async {
    final json = await _mutate(
      () => _api.post(
        '$_base/categories',
        headers: _headers(json: true),
        body: jsonEncode({'name': name, 'kind': kind}),
      ),
    );
    return MoneyCategory.fromJson(
      (json['data'] as Map<String, dynamic>)['category'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteCategory(int id) {
    return _mutate(() => _api.delete('$_base/categories/$id', headers: _headers()));
  }

  Future<MoneyTxnPage> transactions({
    String? cursor,
    int limit = 30,
    String? type,
    int? accountId,
    int? cardId,
    int? categoryId,
    String? search,
    String? from,
    String? to,
    String? merchant,
  }) async {
    if (_offline) return const MoneyTxnPage(items: []);
    final json = await _send(
      () => _api.get(
        '$_base/transactions',
        headers: _headers(),
        query: {
          'limit': '$limit',
          if (cursor != null) 'cursor': cursor,
          if (type != null) 'type': type,
          if (accountId != null) 'accountId': '$accountId',
          if (cardId != null) 'cardId': '$cardId',
          if (categoryId != null) 'categoryId': '$categoryId',
          if (search != null && search.isNotEmpty) 'search': search,
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (merchant != null && merchant.isNotEmpty) 'merchant': merchant,
        },
      ),
    );
    final data = json['data'] as Map<String, dynamic>;
    final pagination = data['pagination'] as Map<String, dynamic>? ?? const {};
    return MoneyTxnPage(
      items: _items(json, 'transactions', MoneyTransaction.fromJson),
      nextCursor: pagination['nextCursor'] as String?,
      hasMore: pagination['hasMore'] == true,
    );
  }

  Future<MoneyTransaction> transaction(int id) async {
    final json = await _send(() => _api.get('$_base/transactions/$id', headers: _headers()));
    return MoneyTransaction.fromJson(
      (json['data'] as Map<String, dynamic>)['transaction'] as Map<String, dynamic>,
    );
  }

  Future<MoneyTransaction> createTransaction(Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.post('$_base/transactions', headers: _headers(json: true), body: jsonEncode(body)),
    );
    return MoneyTransaction.fromJson(
      (json['data'] as Map<String, dynamic>)['transaction'] as Map<String, dynamic>,
    );
  }

  Future<MoneyTransaction> updateTransaction(int id, Map<String, dynamic> body) async {
    final json = await _mutate(
      () => _api.patch(
        '$_base/transactions/$id',
        headers: _headers(json: true),
        body: jsonEncode(body),
      ),
    );
    return MoneyTransaction.fromJson(
      (json['data'] as Map<String, dynamic>)['transaction'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteTransaction(int id) {
    return _mutate(() => _api.delete('$_base/transactions/$id', headers: _headers()));
  }

  Future<List<MoneyTransaction>> search(String query) async {
    if (_offline || query.trim().isEmpty) return const [];
    final page = await transactions(search: query.trim(), limit: 10);
    return page.items;
  }

  Future<MoneyReports> reports({String? month}) async {
    if (_offline) return const MoneyReports();
    final json = await _send(
      () => _api.get(
        '$_base/reports',
        headers: _headers(),
        query: {if (month != null) 'month': month},
      ),
    );
    return MoneyReports.fromJson(json['data'] as Map<String, dynamic>);
  }

  List<T> _items<T>(Map<String, dynamic> json, String key, T Function(Map<String, dynamic>) parse) {
    final raw = (json['data'] as Map<String, dynamic>)[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => parse(Map<String, dynamic>.from(item)))
        .toList();
  }

  Map<String, String> _headers({bool json = false}) => ApiClient.authHeaders(_token(), json: json);

  Future<Map<String, dynamic>> _mutate(Future<http.Response> Function() request) async {
    final json = await _send(request);
    invalidateOverview();
    _onChanged?.call();
    return json;
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    try {
      return await ApiClient.readJson(
        request,
        onError: (message, status) => FinanceException(message, statusCode: status),
      );
    } on FinanceException {
      rethrow;
    } on TimeoutException {
      throw FinanceException('Request timed out for ${ApiConfig.baseUrl}.');
    } catch (_) {
      throw FinanceException(
        'Cannot reach ${ApiConfig.baseUrl}. Check Wi-Fi and that the API is running.',
      );
    }
  }
}
