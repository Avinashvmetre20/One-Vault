import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/planner_models.dart';
import '../../data/planner_service.dart';
import 'planner_screens.dart';

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> with PlannerTickReload {
  String _search = '';
  bool _archived = false;
  bool _loading = true;
  String? _error;
  List<PlannerNote> _items = [];

  PlannerService get _api => AppScope.of(context).planner;

  @override
  Future<void> reloadPlannerData() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent || _items.isEmpty) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    try {
      final page = await _api.notes(
        search: _search,
        scope: _archived ? 'archived' : null,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
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
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            tooltip: _archived ? 'Active notes' : 'Archived notes',
            onPressed: () {
              setState(() => _archived = !_archived);
              _load();
            },
            icon: Icon(_archived ? Icons.inventory_2_outlined : Icons.archive_outlined),
          ),
        ],
      ),
      floatingActionButton: ShellFab(
        heroTag: 'fab-notes',
        tooltip: 'Add note',
        onPressed: () async {
          await context.push(AppRoutes.noteNew);
          if (mounted) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
          children: [
            AppSearchField(
              hintText: 'Search notes',
              onChanged: (value) {
                _search = value;
                _load(silent: true);
              },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              PlannerErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.sticky_note_2_outlined,
                title: 'No notes',
                subtitle: 'Write your first note.',
                action: FilledButton(
                  onPressed: () async {
                    await context.push(AppRoutes.noteNew);
                    if (mounted) _load();
                  },
                  child: const Text('Add note'),
                ),
              )
            else
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTileCard(
                    icon: item.isPinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
                    title: item.title,
                    subtitle: item.content,
                    onTap: () async {
                      await context.push(AppRoutes.noteDetail(item.id));
                      if (mounted) _load();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  PlannerNote? _note;
  bool _loading = true;
  String? _error;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final note = await _api.note(widget.id);
      if (!mounted) return;
      setState(() {
        _note = note;
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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return Scaffold(
      appBar: AppBar(
        title: Text(note?.title ?? 'Note'),
        actions: [
          if (note != null)
            IconButton(
              onPressed: () async {
                await context.push(AppRoutes.noteEdit(note.id));
                if (mounted) _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? PlannerErrorState(message: _error!, onRetry: _load)
          : note == null
          ? const EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: 'Not found',
              subtitle: 'This note was removed.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(note.content, style: const TextStyle(fontSize: 16, height: 1.5)),
                const SizedBox(height: 16),
                if (note.tags.isNotEmpty) Text('Tags: ${note.tags.join(', ')}'),
                if (note.categoryName != null) ...[
                  const SizedBox(height: 8),
                  Text('Category: ${note.categoryName}'),
                ],
                const SizedBox(height: 8),
                Text(
                  note.updatedAt == null
                      ? ''
                      : 'Updated ${Formatters.date(note.updatedAt!)}',
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _run(() => _api.pinNote(note.id)),
                      child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                    ),
                    OutlinedButton(
                      onPressed: () => _run(() => _api.favoriteNote(note.id)),
                      child: Text(note.isFavorite ? 'Unfavorite' : 'Favorite'),
                    ),
                    OutlinedButton(
                      onPressed: () => _run(
                        () => note.isArchived
                            ? _api.restoreNote(note.id)
                            : _api.archiveNote(note.id),
                      ),
                      child: Text(note.isArchived ? 'Restore' : 'Archive'),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    await _run(() => _api.deleteNote(note.id));
                    if (mounted) context.pop();
                  },
                  child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
    );
  }
}

class NoteFormScreen extends StatefulWidget {
  const NoteFormScreen({super.key, this.id});

  final int? id;

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _tags = TextEditingController();
  int? _categoryId;
  List<PlannerCategory> _categories = [];
  bool _saving = false;

  PlannerService get _api => AppScope.of(context).planner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final categories = await _api.noteCategories();
      PlannerNote? existing;
      if (widget.id != null) existing = await _api.note(widget.id!);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoryId = existing?.categoryId ?? categories.firstOrNull?.id;
        if (existing != null) {
          _title.text = existing.title;
          _content.text = existing.content;
          _tags.text = existing.tags.join(', ');
        }
      });
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAppSnack(context, 'Title is required');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final body = {
        'title': _title.text.trim(),
        'content': _content.text.trim(),
        'categoryId': _categoryId,
        'tags': _tags.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
      };
      if (widget.id == null) {
        await _api.createNote(body);
      } else {
        await _api.updateNote(widget.id!, body);
      }
      if (!mounted) return;
      showAppSnack(context, widget.id == null ? 'Note added' : 'Note updated');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: widget.id == null ? 'Add note' : 'Edit note',
      submitLabel: 'Save',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppTextField(
          controller: _title,
          label: 'Title',
          hint: 'Give this note a name',
          prefixIcon: Icons.sticky_note_2_outlined,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _content,
          label: 'Content',
          hint: 'Write something...',
          maxLines: 8,
        ),
        const SizedBox(height: 14),
        AppDropdown<int>(
          label: 'Category',
          hint: 'Choose a category',
          value: _categoryId,
          items: _categories
              .map((item) => DropdownMenuItem(value: item.id, child: Text(item.name)))
              .toList(),
          onChanged: (value) => setState(() => _categoryId = value),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _tags,
          label: 'Tags',
          hint: 'flutter, ideas, personal',
          prefixIcon: Icons.tag,
        ),
      ],
    );
  }
}
