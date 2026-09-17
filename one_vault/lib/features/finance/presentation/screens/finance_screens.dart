import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../app/app_state.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class FinanceDashboardScreen extends StatelessWidget {
  const FinanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Money')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _MoneyStat(
                  label: 'Income',
                  value: Formatters.inr(state.monthlyIncome),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MoneyStat(
                  label: 'Expenses',
                  value: Formatters.inr(state.monthlyExpense),
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MoneyStat(
            label: 'Current balance',
            value: Formatters.inr(state.currentBalance),
          ),
          const SizedBox(height: 24),
          SectionTitle(
            title: 'Accounts',
            action: TextButton(
              onPressed: () => context.push(AppRoutes.accounts),
              child: const Text('See all'),
            ),
          ),
          const SizedBox(height: 8),
          ...state.accounts.take(4).map(
            (account) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTileCard(
                icon: Icons.account_balance_outlined,
                title: account.name,
                subtitle: account.type.label,
                trailing: Text(
                  Formatters.inr(account.balance),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: account.balance < 0 ? AppColors.danger : null,
                  ),
                ),
                onTap: () => context.push(AppRoutes.accounts),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SectionTitle(
            title: 'Recent transactions',
            action: TextButton(
              onPressed: () => context.push(AppRoutes.transactions),
              child: const Text('See all'),
            ),
          ),
          const SizedBox(height: 8),
          ...state.transactions.take(4).map(
            (txn) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TransactionTile(item: txn, state: state),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  const _MoneyStat({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ...state.accounts.map(
            (account) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTileCard(
                icon: Icons.account_balance_wallet_outlined,
                title: account.name,
                subtitle: account.type.label,
                trailing: Text(
                  Formatters.inr(account.balance),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: account.balance < 0 ? AppColors.danger : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-transactions',
        tooltip: 'Add transaction',
        onPressed: () => context.push(AppRoutes.transactionNew),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          ...state.transactions.map(
            (txn) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TransactionTile(item: txn, state: state),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.item, required this.state});

  final TransactionItem item;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final account = state.accountById(item.accountId);
    final isIncome = item.type == TransactionType.income;
    return ListTileCard(
      icon: isIncome ? Icons.south_west : Icons.north_east,
      title: item.merchant,
      subtitle:
          '${item.category} · ${account?.name ?? 'Account'} · ${Formatters.date(item.date)}',
      trailing: Text(
        '${isIncome ? '+' : '-'}${Formatters.inr(item.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: isIncome ? AppColors.success : AppColors.danger,
        ),
      ),
    );
  }
}

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _category = TextEditingController();
  TransactionType _type = TransactionType.expense;
  String? _accountId;
  bool _hydrated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    _hydrated = true;
    _accountId = AppScope.of(context).accounts.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = AppScope.of(context).accounts;

    return FormPage(
      title: 'Add transaction',
      onSubmit: () {
        final amount = double.tryParse(_amount.text.trim());
        if (amount == null || _merchant.text.trim().isEmpty) {
          showAppSnack(context, 'Amount and merchant are required');
          return;
        }
        final state = AppScope.of(context);
        state.addTransaction(
          TransactionItem(
            id: state.nextId('txn'),
            amount: amount,
            date: DateTime.now(),
            accountId: _accountId!,
            category: _category.text.trim().isEmpty ? 'Other' : _category.text.trim(),
            description: _merchant.text.trim(),
            type: _type,
            paymentMethod: 'UPI',
            merchant: _merchant.text.trim(),
          ),
        );
        showAppSnack(context, 'Transaction added');
        context.pop();
      },
      children: [
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _merchant,
          decoration: const InputDecoration(labelText: 'Merchant'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _category,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TransactionType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: TransactionType.values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item.name),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _accountId,
          decoration: const InputDecoration(labelText: 'Account'),
          items: accounts
              .map((item) => DropdownMenuItem(value: item.id, child: Text(item.name)))
              .toList(),
          onChanged: (value) => setState(() => _accountId = value),
        ),
      ],
    );
  }
}
