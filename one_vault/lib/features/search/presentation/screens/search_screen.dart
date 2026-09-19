import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/models/models.dart';
import '../../../finance/data/finance_models.dart';
import '../../../planner/data/planner_models.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';
  List<PlannerSearchHit> _plannerHits = [];
  List<MoneyTransaction> _txnHits = [];

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _plannerHits = [];
        _txnHits = [];
      });
      return;
    }
    try {
      final state = AppScope.of(context);
      final results = await Future.wait([
        state.planner.search(query),
        state.finance.search(query),
      ]);
      if (!mounted) return;
      setState(() {
        _plannerHits = results[0] as List<PlannerSearchHit>;
        _txnHits = results[1] as List<MoneyTransaction>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _plannerHits = [];
        _txnHits = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.trim().toLowerCase();
    final passwordHits = q.isEmpty
        ? <PasswordItem>[]
        : state.passwords
              .where(
                (item) =>
                    item.title.toLowerCase().contains(q) ||
                    item.username.toLowerCase().contains(q) ||
                    item.tags.any((tag) => tag.toLowerCase().contains(q)),
              )
              .toList();
    final documentHits = q.isEmpty
        ? <DocumentItem>[]
        : state.documents.where((item) => item.name.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListView(
        padding: AppDimensions.pagePadding,
        children: [
          AppSearchField(
            hintText: 'Try HDFC, Amazon, insurance...',
            onChanged: (value) {
              setState(() => _query = value);
              _search(value);
            },
          ),
          const SizedBox(height: 20),
          if (q.isEmpty)
            Text(
              'Type to look through passwords, documents, tasks, notes, reminders, and transactions.',
              style: TextStyle(color: AppColors.muted(context)),
            )
          else if (passwordHits.isEmpty &&
              documentHits.isEmpty &&
              _txnHits.isEmpty &&
              _plannerHits.isEmpty)
            Text('No matches for "$q".', style: TextStyle(color: AppColors.muted(context)))
          else ...[
            for (final item in _plannerHits) ...[
              ListTileCard(
                icon: switch (item.type) {
                  'note' => Icons.sticky_note_2_outlined,
                  'reminder' => Icons.notifications_outlined,
                  'alarm' => Icons.alarm,
                  'event' => Icons.event_outlined,
                  _ => Icons.check_circle_outline,
                },
                title: item.title,
                subtitle: item.type[0].toUpperCase() + item.type.substring(1),
                onTap: () {
                  switch (item.type) {
                    case 'note':
                      context.push(AppRoutes.noteDetail(item.id));
                    case 'reminder':
                      context.push(AppRoutes.reminderDetail(item.id));
                    case 'alarm':
                      context.push(AppRoutes.alarmDetail(item.id));
                    case 'event':
                      context.push(AppRoutes.calendarEdit(item.id));
                    default:
                      context.push(AppRoutes.taskDetail(item.id));
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            for (final item in passwordHits) ...[
              ListTileCard(
                icon: Icons.lock_outline,
                title: item.title,
                subtitle: 'Password · ${item.category.label}',
                onTap: () => context.push(AppRoutes.passwordDetail(item.id)),
              ),
              const SizedBox(height: 12),
            ],
            for (final item in documentHits) ...[
              ListTileCard(
                icon: Icons.description_outlined,
                title: item.name,
                subtitle: 'Document · ${item.category.label}',
                onTap: () => context.push(AppRoutes.documentDetail(item.id)),
              ),
              const SizedBox(height: 12),
            ],
            for (final item in _txnHits) ...[
              ListTileCard(
                icon: Icons.receipt_long_outlined,
                title: item.title,
                subtitle: '${Formatters.inrPaise(item.amountPaise)} · ${item.categoryName ?? item.type.label}',
                onTap: () => context.push(AppRoutes.transactionDetail(item.id)),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}
