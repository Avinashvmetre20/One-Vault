import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../data/finance_models.dart';
import '../../data/finance_service.dart';
import '../widgets/money_widgets.dart';

class MoneyReportsScreen extends StatefulWidget {
  const MoneyReportsScreen({super.key});

  @override
  State<MoneyReportsScreen> createState() => _MoneyReportsScreenState();
}

class _MoneyReportsScreenState extends State<MoneyReportsScreen> {
  MoneyReports _reports = const MoneyReports();
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
      final reports = await _api.reports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppDimensions.pagePadding,
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (_error != null)
              MoneyErrorState(message: _error!, onRetry: _load)
            else ...[
              ListTileCard(
                icon: Icons.swap_horiz,
                title: 'Transfers this month',
                subtitle: 'Bank and cash movements',
                trailing: Text(
                  Formatters.inrPaise(_reports.monthlyTransfersPaise),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => context.push(AppRoutes.transfers),
              ),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Category spending'),
              const SizedBox(height: 8),
              if (_reports.categorySpending.isEmpty)
                const EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'No spending yet',
                  subtitle: 'Add expenses to see category totals.',
                )
              else
                for (final item in _reports.categorySpending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTileCard(
                      icon: Icons.category_outlined,
                      title: item.name,
                      subtitle: 'This month',
                      trailing: Text(
                        Formatters.inrPaise(item.amountPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => context.push('${AppRoutes.transactions}?categoryId=${item.id}'),
                    ),
                  ),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Bank-wise spending'),
              const SizedBox(height: 8),
              if (_reports.accountSpending.isEmpty)
                const Text('No bank spending this month.')
              else
                for (final item in _reports.accountSpending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTileCard(
                      icon: Icons.account_balance_outlined,
                      title: item.name,
                      subtitle: 'Expenses',
                      trailing: Text(
                        Formatters.inrPaise(item.amountPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => context.push(AppRoutes.accountDetail(item.id)),
                    ),
                  ),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Card-wise spending'),
              const SizedBox(height: 8),
              if (_reports.cardSpending.isEmpty)
                const Text('No card spending this month.')
              else
                for (final item in _reports.cardSpending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTileCard(
                      icon: Icons.credit_card,
                      title: item.name,
                      subtitle: item.cardType.label,
                      trailing: Text(
                        Formatters.inrPaise(item.purchasesPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => context.push(AppRoutes.cardDetail(item.id)),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
