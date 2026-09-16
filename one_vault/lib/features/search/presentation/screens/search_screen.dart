import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/models/models.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

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
                    item.username.toLowerCase().contains(q),
              )
              .toList();
    final documentHits = q.isEmpty
        ? <DocumentItem>[]
        : state.documents.where((item) => item.name.toLowerCase().contains(q)).toList();
    final noteHits = q.isEmpty
        ? <NoteItem>[]
        : state.notes
              .where(
                (item) =>
                    item.title.toLowerCase().contains(q) ||
                    item.content.toLowerCase().contains(q),
              )
              .toList();
    final txnHits = q.isEmpty
        ? <TransactionItem>[]
        : state.transactions
              .where(
                (item) =>
                    item.merchant.toLowerCase().contains(q) ||
                    item.category.toLowerCase().contains(q),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AppSearchField(
            hintText: 'Try HDFC, Amazon, insurance...',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 20),
          if (q.isEmpty)
            Text(
              'Type to look through dummy passwords, documents, notes, and transactions.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          else if (passwordHits.isEmpty &&
              documentHits.isEmpty &&
              noteHits.isEmpty &&
              txnHits.isEmpty)
            Text('No matches for "$q".', style: TextStyle(color: Colors.grey.shade600))
          else ...[
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
            for (final item in noteHits) ...[
              ListTileCard(
                icon: Icons.sticky_note_2_outlined,
                title: item.title,
                subtitle: 'Note',
                onTap: () => context.push(AppRoutes.noteDetail(item.id)),
              ),
              const SizedBox(height: 12),
            ],
            for (final item in txnHits) ...[
              ListTileCard(
                icon: Icons.receipt_long_outlined,
                title: item.merchant,
                subtitle: '${Formatters.inr(item.amount)} · ${item.category}',
                onTap: () => context.go(AppRoutes.transactions),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}
