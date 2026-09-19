import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/finance_models.dart';
import '../../data/finance_service.dart';
import '../widgets/money_widgets.dart';
import 'finance_screens.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.forcedType});

  final String? forcedType;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> with FinanceTickReload {
  final _items = <MoneyTransaction>[];
  String _search = '';
  String? _type;
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  FinanceService get _api => AppScope.of(context).finance;

  @override
  Future<void> reloadFinanceData() => _load(reset: true, silent: true);

  @override
  void initState() {
    super.initState();
    _type = widget.forcedType;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (reset) {
      _cursor = null;
      if (!silent) {
        setState(() {
          _loading = _items.isEmpty;
          _error = null;
        });
      }
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await _api.transactions(
        cursor: reset ? null : _cursor,
        search: _search,
        type: _type,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _add() async {
    final type = widget.forcedType != null
        ? moneyTxnTypeFrom(widget.forcedType)
        : await showTransactionTypeSheet(context);
    if (type == null || !mounted) return;
    await context.push('${AppRoutes.transactionNew}?type=${type.api}');
    if (mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in _items) {
      final key = _dayLabel(item.occurredAt);
      groups.putIfAbsent(key, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.forcedType == 'transfer' ? 'Transfers' : 'Transactions')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-txns',
        tooltip: 'Add transaction',
        onPressed: _add,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 240) {
            _load();
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppDimensions.pagePaddingFab,
            children: [
              AppSearchField(
                hintText: 'Search Amazon, Swiggy, salary...',
                onChanged: (value) {
                  _search = value;
                  _load(reset: true, silent: true);
                },
              ),
              if (widget.forcedType == null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [
                      (null, 'All'),
                      ('expense', 'Expense'),
                      ('income', 'Income'),
                      ('transfer', 'Transfer'),
                      ('card_purchase', 'Cards'),
                      ('refund', 'Refund'),
                    ])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: _type == item.$1,
                        onSelected: (_) {
                          setState(() => _type = item.$1);
                          _load(reset: true);
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (_error != null)
                MoneyErrorState(message: _error!, onRetry: () => _load(reset: true))
              else if (_items.isEmpty)
                EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  subtitle: 'Start tracking your money.',
                  action: FilledButton(onPressed: _add, child: const Text('Add Transaction')),
                )
              else ...[
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 8),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted(context),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final item in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TransactionTile(
                        item: item,
                        onTap: () async {
                          await context.push(AppRoutes.transactionDetail(item.id));
                          if (mounted) _load(reset: true, silent: true);
                        },
                      ),
                    ),
                ],
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _dayLabel(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'TODAY';
    if (day == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('dd MMM yyyy').format(local).toUpperCase();
  }
}

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  MoneyTransaction? _item;
  bool _loading = true;
  String? _error;

  FinanceService get _api => AppScope.of(context).finance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final item = await _api.transaction(widget.id);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (error is FinanceException && error.statusCode == 404) {
        context.pop();
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: Text(item?.title ?? 'Transaction'),
        actions: [
          if (item != null)
            IconButton(
              onPressed: () async {
                await context.push(AppRoutes.transactionEdit(item.id));
                if (mounted) _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? MoneyErrorState(message: _error!, onRetry: _load)
          : item == null
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Not found', subtitle: 'This transaction was removed.')
          : ListView(
              padding: AppDimensions.pagePadding,
              children: [
                Text(
                  '${item.showsAsCredit ? '+' : (item.type.isTransfer ? '' : '-')}${Formatters.inrPaise(item.amountPaise)}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: item.showsAsCredit
                        ? AppColors.success
                        : item.type.isTransfer
                        ? null
                        : AppColors.danger,
                  ),
                ),
                const SizedBox(height: 8),
                Text(item.type.label, style: TextStyle(color: AppColors.muted(context))),
                const SizedBox(height: 20),
                if (item.categoryName != null) InfoRow(label: 'Category', value: item.categoryName!),
                if (item.sourceLabel.isNotEmpty) InfoRow(label: 'Account', value: item.sourceLabel),
                if (item.paymentMethod.isNotEmpty) InfoRow(label: 'Payment', value: item.paymentMethod),
                InfoRow(label: 'Date', value: Formatters.date(item.occurredAt)),
                if (item.merchantName.isNotEmpty) InfoRow(label: 'Merchant', value: item.merchantName),
                if (item.description.isNotEmpty) InfoRow(label: 'Notes', value: item.description),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('${AppRoutes.transactionNew}?type=${item.type.api}&duplicate=${item.id}'),
                  child: const Text('Duplicate'),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showAppConfirm(
                      context,
                      title: 'Delete this transaction?',
                      message: 'This will update account and card balances.',
                    );
                    if (!confirmed || !mounted) return;
                    try {
                      await _api.deleteTransaction(item.id);
                      if (!mounted) return;
                      showAppSnack(context, 'Transaction deleted');
                      context.pop();
                    } catch (error) {
                      if (error is FinanceException && error.statusCode == 404) {
                        if (mounted) context.pop();
                        return;
                      }
                      if (mounted) showAppSnack(context, error.toString());
                    }
                  },
                  child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
    );
  }
}

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key, this.id, this.initialType});

  final int? id;
  final String? initialType;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _merchant = TextEditingController();
  final _notes = TextEditingController();
  late final String _clientId;
  MoneyTxnType _type = MoneyTxnType.expense;
  DateTime _date = DateTime.now();
  int? _accountId;
  int? _toAccountId;
  int? _cardId;
  int? _categoryId;
  List<MoneyAccount> _accounts = [];
  List<MoneyCard> _cards = [];
  List<MoneyCategory> _categories = [];
  bool _saving = false;

  FinanceService get _api => AppScope.of(context).finance;
  bool get _isEdit => widget.id != null;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _type = moneyTxnTypeFrom(widget.initialType ?? 'expense');
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final results = await Future.wait([
        _api.accounts(),
        _api.cards(),
        _api.categories(),
      ]);
      final accounts = results[0] as List<MoneyAccount>;
      final cards = results[1] as List<MoneyCard>;
      final categories = results[2] as List<MoneyCategory>;
      MoneyTransaction? existing;
      if (widget.id != null) existing = await _api.transaction(widget.id!);

      int? lastAccount;
      int? lastCategory;
      if (existing == null && accounts.length == 1) {
        lastAccount = accounts.first.id;
      } else if (existing == null) {
        lastAccount = await _api.lastAccountId();
        lastCategory = await _api.lastCategoryId();
        if (lastAccount != null && !accounts.any((item) => item.id == lastAccount)) {
          lastAccount = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _cards = cards;
        _categories = categories;
        if (existing != null) {
          _type = existing.type;
          _amount.text = paiseToApi(existing.amountPaise);
          _title.text = existing.title;
          _merchant.text = existing.merchantName;
          _notes.text = existing.description;
          _date = existing.occurredAt.toLocal();
          _accountId = existing.accountId;
          _toAccountId = existing.counterpartyAccountId;
          _cardId = existing.cardId;
          _categoryId = existing.categoryId;
        } else {
          _accountId = lastAccount;
          _categoryId = lastCategory;
          if (_type == MoneyTxnType.cardPurchase && cards.length == 1) {
            _cardId = cards.first.id;
          }
        }
      });
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _merchant.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<MoneyCategory> get _visibleCategories {
    if (_type == MoneyTxnType.income) {
      return _categories.where((item) => item.kind == CategoryKind.income).toList();
    }
    if (_type == MoneyTxnType.cardPayment) {
      return _categories.where((item) => item.kind == CategoryKind.financial).toList();
    }
    return _categories.where((item) => item.kind != CategoryKind.income).toList();
  }

  Future<void> _save() async {
    final amount = parsePaise(_amount.text.trim());
    if (amount <= 0) {
      showAppSnack(context, 'Amount must be greater than 0');
      return;
    }
    if (_title.text.trim().isEmpty) {
      showAppSnack(context, 'Title is required');
      return;
    }
    if (_type == MoneyTxnType.transfer && (_accountId == null || _toAccountId == null)) {
      showAppSnack(context, 'Choose from and to accounts');
      return;
    }
    if ((_type == MoneyTxnType.expense || _type == MoneyTxnType.income) && _accountId == null && _cardId == null) {
      showAppSnack(context, 'Account is required');
      return;
    }
    if ((_type == MoneyTxnType.cardPurchase || _type == MoneyTxnType.cardPayment) && _cardId == null) {
      showAppSnack(context, 'Card is required');
      return;
    }
    if (_type == MoneyTxnType.cardPayment && _accountId == null) {
      showAppSnack(context, 'Payment account is required');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final body = {
        'transactionType': _type.api,
        'title': _title.text.trim(),
        'amount': paiseToApi(amount),
        'occurredAt': DateTime(_date.year, _date.month, _date.day, 12).toUtc().toIso8601String(),
        'merchantName': _merchant.text.trim(),
        'description': _notes.text.trim(),
        'categoryId': _categoryId,
        'accountId': _accountId,
        'counterpartyAccountId': _toAccountId,
        'cardId': _cardId,
        if (!_isEdit) 'clientTransactionId': _clientId,
      };
      if (_isEdit) {
        await _api.updateTransaction(widget.id!, body);
      } else {
        await _api.createTransaction(body);
        await _api.rememberSelection(accountId: _accountId, categoryId: _categoryId);
      }
      if (!mounted) return;
      showAppSnack(context, _isEdit ? 'Transaction updated' : 'Transaction added');
      context.pop();
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _date = selected);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visibleCategories;
    final creditCards = _cards.where((item) => item.isCredit).toList();
    final debitCards = _cards.where((item) => !item.isCredit).toList();

    return FormPage(
      title: _isEdit ? 'Edit transaction' : _type.label,
      submitLabel: _type == MoneyTxnType.transfer ? 'Transfer' : 'Save',
      submitting: _saving,
      onSubmit: _save,
      children: [
        if (_type == MoneyTxnType.expense || _type == MoneyTxnType.income || _type == MoneyTxnType.refund)
          AppDropdown<int>(
            label: 'Account',
            value: _accountId,
            items: _accounts
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _accountId = value),
          ),
        if (_type == MoneyTxnType.expense && debitCards.isNotEmpty) ...[
          AppDimensions.fieldGap,
          AppDropdown<int>(
            label: 'Debit card (optional)',
            value: _cardId,
            hint: 'None',
            items: debitCards
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _cardId = value),
          ),
        ],
        if (_type == MoneyTxnType.transfer) ...[
          AppDropdown<int>(
            label: 'From',
            value: _accountId,
            items: _accounts
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _accountId = value),
          ),
          AppDimensions.fieldGap,
          AppDropdown<int>(
            label: 'To',
            value: _toAccountId,
            items: _accounts
                .where((item) => item.id != _accountId)
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _toAccountId = value),
          ),
        ],
        if (_type == MoneyTxnType.cardPurchase)
          AppDropdown<int>(
            label: 'Card',
            value: _cardId,
            items: _cards
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _cardId = value),
          ),
        if (_type == MoneyTxnType.cardPayment) ...[
          AppDropdown<int>(
            label: 'Credit card',
            value: _cardId,
            items: creditCards
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _cardId = value),
          ),
          AppDimensions.fieldGap,
          AppDropdown<int>(
            label: 'Pay from',
            value: _accountId,
            items: _accounts
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _accountId = value),
          ),
        ],
        if (_type == MoneyTxnType.refund && creditCards.isNotEmpty) ...[
          AppDimensions.fieldGap,
          AppDropdown<int>(
            label: 'Credit card (optional)',
            value: _cardId,
            hint: 'Bank/cash refund',
            items: creditCards
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
                .toList(),
            onChanged: (value) => setState(() => _cardId = value),
          ),
        ],
        AppDimensions.fieldGap,
        AppTextField(
          controller: _amount,
          label: 'Amount (₹)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _title, label: 'Title'),
        if (_type != MoneyTxnType.transfer) ...[
          AppDimensions.fieldGap,
          AppDropdown<int>(
            label: 'Category',
            value: categories.any((item) => item.id == _categoryId) ? _categoryId : null,
            hint: 'Optional',
            items: categories
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.name)))
                .toList(),
            onChanged: (value) => setState(() => _categoryId = value),
          ),
          AppDimensions.fieldGap,
          AppTextField(controller: _merchant, label: 'Merchant'),
        ],
        AppDimensions.fieldGap,
        AppPickerField(
          label: 'Date',
          value: Formatters.date(_date),
          icon: Icons.event_outlined,
          onTap: _pickDate,
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
      ],
    );
  }
}
