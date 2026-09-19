import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../data/finance_models.dart';
import '../../data/finance_service.dart';
import '../widgets/money_widgets.dart';

mixin FinanceTickReload<T extends StatefulWidget> on State<T> {
  ValueNotifier<int>? _tick;

  @protected
  Future<void> reloadFinanceData();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).financeTick;
    if (!identical(_tick, tick)) {
      _tick?.removeListener(_onTick);
      _tick = tick;
      _tick!.addListener(_onTick);
    }
  }

  void _onTick() {
    if (mounted) reloadFinanceData();
  }

  @override
  void dispose() {
    _tick?.removeListener(_onTick);
    super.dispose();
  }
}

Future<MoneyTxnType?> showTransactionTypeSheet(BuildContext context) {
  const types = [
    MoneyTxnType.expense,
    MoneyTxnType.income,
    MoneyTxnType.transfer,
    MoneyTxnType.cardPurchase,
    MoneyTxnType.cardPayment,
    MoneyTxnType.refund,
  ];
  return showModalBottomSheet<MoneyTxnType>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What happened?', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final type in types)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_typeIcon(type)),
                  title: Text(type.label),
                  onTap: () => Navigator.pop(context, type),
                ),
            ],
          ),
        ),
      );
    },
  );
}

IconData _typeIcon(MoneyTxnType type) {
  return switch (type) {
    MoneyTxnType.income => Icons.south_west,
    MoneyTxnType.transfer || MoneyTxnType.cashWithdrawal || MoneyTxnType.cashDeposit => Icons.swap_horiz,
    MoneyTxnType.refund => Icons.replay,
    MoneyTxnType.cardPurchase || MoneyTxnType.cardPayment => Icons.credit_card,
    _ => Icons.north_east,
  };
}

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen>
    with FinanceTickReload {
  MoneyOverview _overview = const MoneyOverview();
  bool _loading = true;
  bool _opened = false;
  String? _error;
  ValueNotifier<int>? _shellIndex;

  FinanceService get _api => AppScope.of(context).finance;
  static const _moneyTab = 2;

  @override
  Future<void> reloadFinanceData() {
    if (!_opened) return Future.value();
    return _load(silent: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final index = AppScope.of(context).shellTabIndex;
    if (!identical(_shellIndex, index)) {
      _shellIndex?.removeListener(_onShellTab);
      _shellIndex = index;
      _shellIndex!.addListener(_onShellTab);
    }
    _onShellTab();
  }

  void _onShellTab() {
    if (!mounted) return;
    if (_shellIndex?.value != _moneyTab) return;
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final overview = await _api.loadOverview(force: !silent);
      if (!mounted) return;
      setState(() {
        _overview = overview;
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
  void dispose() {
    _shellIndex?.removeListener(_onShellTab);
    super.dispose();
  }

  Future<void> _addTransaction() async {
    if (_overview.accounts.isEmpty) {
      await context.push(AppRoutes.accountNew);
      if (mounted) _load();
      return;
    }
    final type = await showTransactionTypeSheet(context);
    if (type == null || !mounted) return;
    await context.push('${AppRoutes.transactionNew}?type=${type.api}');
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Manage',
            onSelected: (value) async {
              await context.push(value);
              if (mounted) _load(silent: true);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: AppRoutes.accounts, child: Text('Accounts')),
              PopupMenuItem(value: AppRoutes.cards, child: Text('Cards')),
              PopupMenuItem(value: AppRoutes.moneyCategories, child: Text('Categories')),
              PopupMenuItem(value: AppRoutes.transfers, child: Text('Transfers')),
              PopupMenuItem(value: AppRoutes.moneyReports, child: Text('Reports')),
            ],
          ),
        ],
      ),
      floatingActionButton: ShellFab(
        heroTag: 'fab-money',
        tooltip: 'Add transaction',
        onPressed: _addTransaction,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppDimensions.pagePaddingFab,
          children: [
            if (_error != null)
              MoneyErrorState(message: _error!, onRetry: _load)
            else if (_loading && _overview.accounts.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_overview.accounts.isEmpty)
              EmptyState(
                icon: Icons.account_balance_outlined,
                title: 'No accounts added yet',
                subtitle: 'Add your accounts to start tracking your money.',
                action: FilledButton(
                  onPressed: () async {
                    await context.push(AppRoutes.accountNew);
                    if (mounted) _load();
                  },
                  child: const Text('Add Bank Account'),
                ),
              )
            else ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash & bank', style: TextStyle(color: AppColors.muted(context))),
                    const SizedBox(height: 6),
                    Text(
                      Formatters.inrPaise(_overview.cashAndBankPaise),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            label: 'Income',
                            value: Formatters.inrPaise(_overview.monthlyIncomePaise),
                            color: AppColors.success,
                          ),
                        ),
                        Expanded(
                          child: _MiniStat(
                            label: 'Expenses',
                            value: Formatters.inrPaise(_overview.monthlyExpensePaise),
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    if (_overview.creditCardOutstandingPaise != 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Credit card outstanding ${Formatters.inrPaise(_overview.creditCardOutstandingPaise)}',
                        style: TextStyle(color: AppColors.muted(context)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                title: 'Accounts',
                action: TextButton(
                  onPressed: () async {
                    await context.push(AppRoutes.accounts);
                    if (mounted) _load(silent: true);
                  },
                  child: const Text('View all'),
                ),
              ),
              const SizedBox(height: 8),
              for (final account in _overview.accounts.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTileCard(
                    icon: account.kind == AccountKind.cash
                        ? Icons.payments_outlined
                        : Icons.account_balance_outlined,
                    title: account.name,
                    subtitle: account.kind.label,
                    trailing: Text(
                      Formatters.inrPaise(account.currentBalancePaise),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () async {
                      await context.push(AppRoutes.accountDetail(account.id));
                      if (mounted) _load(silent: true);
                    },
                  ),
                ),
              if (_overview.creditCards.isNotEmpty) ...[
                const SizedBox(height: 8),
                SectionTitle(
                  title: 'Credit cards',
                  action: TextButton(
                    onPressed: () => context.push(AppRoutes.cards),
                    child: const Text('View all'),
                  ),
                ),
                const SizedBox(height: 8),
                for (final card in _overview.creditCards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTileCard(
                      icon: Icons.credit_card,
                      title: card.name,
                      subtitle: 'Outstanding',
                      trailing: Text(
                        Formatters.inrPaise(card.currentOutstandingPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
                      ),
                      onTap: () => context.push(AppRoutes.cardDetail(card.id)),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              SectionTitle(
                title: 'Recent transactions',
                action: TextButton(
                  onPressed: () => context.push(AppRoutes.transactions),
                  child: const Text('View all'),
                ),
              ),
              const SizedBox(height: 8),
              if (_overview.recentTransactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    subtitle: 'Start tracking your money.',
                  ),
                )
              else
                for (final item in _overview.recentTransactions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TransactionTile(
                      item: item,
                      onTap: () => context.push(AppRoutes.transactionDetail(item.id)),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.muted(context), fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}
