import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/finance_models.dart';
import '../../data/finance_service.dart';
import '../widgets/money_widgets.dart';
import 'finance_screens.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> with FinanceTickReload {
  List<MoneyAccount> _items = [];
  bool _loading = true;
  String? _error;

  FinanceService get _api => AppScope.of(context).finance;

  @override
  Future<void> reloadFinanceData() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final items = await _api.accounts();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = _items.where((item) => item.kind == AccountKind.bank).toList();
    final cash = _items.where((item) => item.kind == AccountKind.cash).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-accounts',
        tooltip: 'Add account',
        onPressed: () async {
          await context.push(AppRoutes.accountNew);
          if (mounted) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppDimensions.pagePaddingFab,
          children: [
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_error != null)
              MoneyErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.account_balance_outlined,
                title: 'No bank accounts yet',
                subtitle: 'Add HDFC, SBI, cash, or any account you use.',
                action: FilledButton(
                  onPressed: () => context.push(AppRoutes.accountNew),
                  child: const Text('Add Account'),
                ),
              )
            else ...[
              if (banks.isNotEmpty) ...[
                const SectionTitle(title: 'Bank accounts'),
                const SizedBox(height: 8),
                for (final item in banks) _tile(item),
              ],
              if (cash.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionTitle(title: 'Cash'),
                const SizedBox(height: 8),
                for (final item in cash) _tile(item),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(MoneyAccount item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTileCard(
        icon: item.kind == AccountKind.cash
            ? Icons.payments_outlined
            : Icons.account_balance_outlined,
        title: item.name,
        subtitle: [
          if (item.bankAccountType != null) item.bankAccountType!.label,
          if (item.lastFourDigits != null) maskedLastFour(item.lastFourDigits),
        ].where((part) => part.isNotEmpty).join(' · '),
        trailing: Text(
          Formatters.inrPaise(item.currentBalancePaise),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: item.currentBalancePaise < 0 ? AppColors.danger : null,
          ),
        ),
        onTap: () async {
          await context.push(AppRoutes.accountDetail(item.id));
          if (mounted) _load();
        },
      ),
    );
  }
}

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  MoneyAccount? _account;
  List<MoneyTransaction> _recent = [];
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
      final results = await Future.wait([
        _api.account(widget.id),
        _api.transactions(accountId: widget.id, limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _account = results[0] as MoneyAccount;
        _recent = (results[1] as MoneyTxnPage).items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    return Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? 'Account'),
        actions: [
          if (account != null)
            IconButton(
              onPressed: () async {
                await context.push(AppRoutes.accountEdit(account.id));
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
          : account == null
          ? const EmptyState(icon: Icons.account_balance_outlined, title: 'Not found', subtitle: 'This account was removed.')
          : ListView(
              padding: AppDimensions.pagePadding,
              children: [
                Text(
                  Formatters.inrPaise(account.currentBalancePaise),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                if (account.monthlyIncomePaise != null)
                  InfoRow(label: 'This month income', value: Formatters.inrPaise(account.monthlyIncomePaise!)),
                if (account.monthlyExpensePaise != null)
                  InfoRow(label: 'This month expenses', value: Formatters.inrPaise(account.monthlyExpensePaise!)),
                if (account.monthlyTransfersPaise != null)
                  InfoRow(label: 'This month transfers', value: Formatters.inrPaise(account.monthlyTransfersPaise!)),
                InfoRow(label: 'Type', value: account.kind == AccountKind.cash ? 'Cash' : (account.bankAccountType?.label ?? 'Bank')),
                if (account.lastFourDigits != null)
                  InfoRow(label: 'Account', value: maskedLastFour(account.lastFourDigits)),
                InfoRow(label: 'Opening balance', value: Formatters.inrPaise(account.openingBalancePaise)),
                if (account.notes.isNotEmpty) InfoRow(label: 'Notes', value: account.notes),
                const SizedBox(height: 8),
                const SectionTitle(title: 'Recent transactions'),
                const SizedBox(height: 8),
                if (_recent.isEmpty)
                  Text('No transactions yet.', style: TextStyle(color: AppColors.muted(context)))
                else
                  for (final item in _recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TransactionTile(
                        item: item,
                        onTap: () => context.push(AppRoutes.transactionDetail(item.id)),
                      ),
                    ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showAppConfirm(
                      context,
                      title: 'Archive this account?',
                      message: 'Historical transactions stay. It will no longer appear as a source.',
                      confirmLabel: 'Archive',
                    );
                    if (!confirmed || !mounted) return;
                    try {
                      await _api.archiveAccount(account.id);
                      if (!mounted) return;
                      showAppSnack(context, 'Account archived');
                      context.pop();
                    } catch (error) {
                      if (mounted) showAppSnack(context, error.toString());
                    }
                  },
                  child: const Text('Archive', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
    );
  }
}

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, this.id});

  final int? id;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _name = TextEditingController();
  final _institution = TextEditingController();
  final _lastFour = TextEditingController();
  final _opening = TextEditingController();
  final _notes = TextEditingController();
  AccountKind _kind = AccountKind.bank;
  BankAccountType _bankType = BankAccountType.savings;
  bool _saving = false;
  bool _hydrated = false;

  FinanceService get _api => AppScope.of(context).finance;
  bool get _isEdit => widget.id != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    if (_hydrated || widget.id == null) return;
    _hydrated = true;
    try {
      final account = await _api.account(widget.id!);
      if (!mounted) return;
      setState(() {
        _name.text = account.name;
        _institution.text = account.institutionName;
        _lastFour.text = account.lastFourDigits ?? '';
        _opening.text = paiseToApi(account.openingBalancePaise);
        _notes.text = account.notes;
        _kind = account.kind;
        _bankType = account.bankAccountType ?? BankAccountType.savings;
      });
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _lastFour.dispose();
    _opening.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAppSnack(context, 'Account name is required');
      return;
    }
    if (_kind == AccountKind.bank && _lastFour.text.trim().isNotEmpty && _lastFour.text.replaceAll(RegExp(r'\D'), '').length != 4) {
      showAppSnack(context, 'Last 4 digits must be exactly 4 numbers');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'institutionName': _institution.text.trim(),
        'accountKind': _kind.api,
        'bankAccountType': _kind == AccountKind.cash ? null : _bankType.api,
        'lastFourDigits': _kind == AccountKind.cash ? null : _lastFour.text.replaceAll(RegExp(r'\D'), ''),
        'openingBalance': _opening.text.trim().isEmpty ? '0.00' : _opening.text.trim(),
        'notes': _notes.text.trim(),
      };
      if (_isEdit) {
        await _api.updateAccount(widget.id!, body);
      } else {
        await _api.createAccount(body);
      }
      if (!mounted) return;
      showAppSnack(context, _isEdit ? 'Account updated' : 'Account added');
      context.pop();
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _isEdit ? 'Edit account' : 'Add account',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppDropdown<AccountKind>(
          label: 'Kind',
          value: _kind,
          items: AccountKind.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _kind = value ?? _kind),
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _name, label: _kind == AccountKind.cash ? 'Name' : 'Account name'),
        if (_kind == AccountKind.bank) ...[
          AppDimensions.fieldGap,
          AppTextField(controller: _institution, label: 'Bank name'),
          AppDimensions.fieldGap,
          AppDropdown<BankAccountType>(
            label: 'Account type',
            value: _bankType,
            items: BankAccountType.values
                .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                .toList(),
            onChanged: (value) => setState(() => _bankType = value ?? _bankType),
          ),
          AppDimensions.fieldGap,
          AppTextField(
            controller: _lastFour,
            label: 'Last 4 digits',
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),
        ],
        AppDimensions.fieldGap,
        AppTextField(
          controller: _opening,
          label: _isEdit ? 'Opening balance (₹)' : 'Opening / current balance (₹)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
      ],
    );
  }
}
