import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/action_card.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../app/app_state.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiClient();
  bool? _healthy;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    final ok = await _api.checkHealth();
    if (!mounted) return;
    setState(() => _healthy = ok);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padding = AppDimensions.horizontalPadding(width);
            return RefreshIndicator(
              onRefresh: _checkHealth,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 24, padding, 16),
                  sliver: SliverToBoxAdapter(
                    child: _HomeHeader(
                      name: state.profile.name,
                      healthy: _healthy,
                      onOpenProfile: () => context.push(AppRoutes.profile),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 16),
                  sliver: SliverToBoxAdapter(
                    child: AppSearchField(
                      hintText: 'Search passwords, notes, bills...',
                      readOnly: true,
                      onTap: () => context.push(AppRoutes.search),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: const SliverToBoxAdapter(child: _WelcomeCard()),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 28, padding, 12),
                  sliver: const SliverToBoxAdapter(
                    child: SectionTitle(title: 'This month'),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: SliverToBoxAdapter(child: _FinanceSummary(state: state)),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 28, padding, 12),
                  sliver: const SliverToBoxAdapter(
                    child: SectionTitle(title: 'Quick Actions'),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: SliverToBoxAdapter(
                    child: _ResponsiveActionGrid(
                      availableWidth: width - (padding * 2),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 28, padding, 12),
                  sliver: SliverToBoxAdapter(
                    child: SectionTitle(
                      title: "Today's tasks",
                      action: TextButton(
                        onPressed: () => context.go(AppRoutes.tasks),
                        child: const Text('See all'),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: const SliverToBoxAdapter(child: _TodayTasks()),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 28, padding, 12),
                  sliver: const SliverToBoxAdapter(
                    child: SectionTitle(title: 'Upcoming'),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: const SliverToBoxAdapter(child: _UpcomingItems()),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 28, padding, 12),
                  sliver: const SliverToBoxAdapter(
                    child: SectionTitle(title: 'Recent'),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 30),
                  sliver: const SliverToBoxAdapter(child: _RecentItems()),
                ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.name,
    required this.healthy,
    required this.onOpenProfile,
  });

  final String name;
  final bool? healthy;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _greetingFor(DateTime.now()),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.muted(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HealthDot(healthy: healthy),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Formatters.weekdayDate(DateTime.now()),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: onOpenProfile,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line(context)),
            ),
            child: const Icon(Icons.person_outline, size: 26),
          ),
        ),
      ],
    );
  }
}

class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.healthy});

  final bool? healthy;

  @override
  Widget build(BuildContext context) {
    final color = healthy == true
        ? AppColors.success
        : healthy == false
            ? AppColors.danger
            : AppColors.muted(context);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

String _greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: Colors.white, size: 34),
          const SizedBox(height: 18),
          Text(
            'OneVault',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep your important information secure and organized.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go(AppRoutes.vault),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Get Started',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Income',
                value: Formatters.inr(state.monthlyIncome),
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatChip(
                label: 'Expenses',
                value: Formatters.inr(state.monthlyExpense),
                color: AppColors.danger,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Balance',
                value: Formatters.inr(state.currentBalance),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatChip(
                label: 'Savings',
                value: Formatters.inr(state.monthlySavings),
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
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
          Text(label, style: TextStyle(color: AppColors.muted(context), fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveActionGrid extends StatelessWidget {
  const _ResponsiveActionGrid({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    final columns = availableWidth >= 700
        ? 4
        : availableWidth >= 450
        ? 3
        : 2;
    const spacing = AppDimensions.gridSpacing;
    final cardWidth = (availableWidth - (spacing * (columns - 1))) / columns;
    final childAspectRatio = cardWidth / AppDimensions.minActionCardHeight;

    return GridView.count(
      crossAxisCount: columns,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: childAspectRatio,
      children: [
        ActionCard(
          icon: Icons.badge_outlined,
          title: 'My Profile',
          subtitle: 'Personal details',
          onTap: () => context.push(AppRoutes.profile),
        ),
        ActionCard(
          icon: Icons.lock_outline,
          title: 'Passwords',
          subtitle: 'Secure credentials',
          onTap: () => context.go(AppRoutes.passwords),
        ),
        ActionCard(
          icon: Icons.description_outlined,
          title: 'Documents',
          subtitle: 'Important files',
          onTap: () => context.go(AppRoutes.documents),
        ),
        ActionCard(
          icon: Icons.settings_outlined,
          title: 'Settings',
          subtitle: 'App preferences',
          onTap: () => context.push(AppRoutes.settings),
        ),
      ],
    );
  }
}

class _TodayTasks extends StatelessWidget {
  const _TodayTasks();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Text('Open Planner to see tasks due today.'),
    );
  }
}

class _UpcomingItems extends StatelessWidget {
  const _UpcomingItems();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final expiries = state.documents.where((item) => item.expiryDate != null).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));

    return Column(
      children: [
        ListTileCard(
          icon: Icons.credit_card,
          title: 'Credit card due',
          subtitle: '22 Sep 2026 · HDFC Credit Card',
          onTap: () => context.go(AppRoutes.money),
        ),
        if (expiries.isNotEmpty) ...[
          const SizedBox(height: 12),
          ListTileCard(
            icon: Icons.event_busy_outlined,
            title: '${expiries.first.name} expires',
            subtitle: Formatters.date(expiries.first.expiryDate!),
            onTap: () => context.push(AppRoutes.documentDetail(expiries.first.id)),
          ),
        ],
      ],
    );
  }
}

class _RecentItems extends StatelessWidget {
  const _RecentItems();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final recentTxn = state.transactions.first;
    final recentDoc = state.documents.first;

    return Column(
      children: [
        ListTileCard(
          icon: Icons.receipt_long_outlined,
          title: recentTxn.merchant,
          subtitle:
              '${recentTxn.type == TransactionType.income ? '+' : '-'}${Formatters.inr(recentTxn.amount)} · ${recentTxn.category}',
          onTap: () => context.go(AppRoutes.transactions),
        ),
        const SizedBox(height: 12),
        ListTileCard(
          icon: Icons.description_outlined,
          title: recentDoc.name,
          subtitle: recentDoc.category.label,
          onTap: () => context.push(AppRoutes.documentDetail(recentDoc.id)),
        ),
      ],
    );
  }
}
