import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class NoteListScreen extends StatelessWidget {
  const NoteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notes = [...AppScope.of(context).notes]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-notes',
        onPressed: () => context.push(AppRoutes.noteNew),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          if (notes.isEmpty)
            const EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: 'No notes',
              subtitle: 'Write your first note.',
            )
          else
            ...notes.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTileCard(
                  icon: item.isPinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
                  title: item.title,
                  subtitle: item.content,
                  onTap: () => context.push(AppRoutes.noteDetail(item.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NoteDetailScreen extends StatelessWidget {
  const NoteDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final item = AppScope.of(context).notes.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.sticky_note_2_outlined,
          title: 'Not found',
          subtitle: 'This note was removed.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(item.content, style: const TextStyle(fontSize: 16, height: 1.5)),
          const SizedBox(height: 16),
          Text('Tags: ${item.tags.join(', ')}'),
          const SizedBox(height: 8),
          Text('Updated ${Formatters.date(item.updatedAt)}'),
        ],
      ),
    );
  }
}

class NoteFormScreen extends StatefulWidget {
  const NoteFormScreen({super.key});

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add note',
      onSubmit: () {
        if (_title.text.trim().isEmpty) {
          showAppSnack(context, 'Title is required');
          return;
        }
        final state = AppScope.of(context);
        state.addNote(
          NoteItem(
            id: state.nextId('note'),
            title: _title.text.trim(),
            content: _content.text.trim(),
            tags: const [],
            updatedAt: DateTime.now(),
          ),
        );
        showAppSnack(context, 'Note added');
        context.pop();
      },
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _content,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Content'),
        ),
      ],
    );
  }
}
