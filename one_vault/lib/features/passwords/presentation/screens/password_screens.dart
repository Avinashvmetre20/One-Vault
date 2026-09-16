import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../app/app_state.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class PasswordListScreen extends StatefulWidget {
  const PasswordListScreen({super.key});

  @override
  State<PasswordListScreen> createState() => _PasswordListScreenState();
}

class _PasswordListScreenState extends State<PasswordListScreen> {
  String _query = '';
  PasswordCategory? _category;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.passwords.where((item) {
      final matchesQuery =
          _query.isEmpty ||
          item.title.toLowerCase().contains(_query.toLowerCase()) ||
          item.username.toLowerCase().contains(_query.toLowerCase());
      final matchesCategory = _category == null || item.category == _category;
      return matchesQuery && matchesCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passwords'),
        actions: [
          IconButton(
            tooltip: 'Generator',
            onPressed: () => context.push(AppRoutes.passwordGenerator),
            icon: const Icon(Icons.password),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-passwords',
        onPressed: () => context.push(AppRoutes.passwordNew),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          AppSearchField(
            hintText: 'Search passwords',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _category == null,
                  onTap: () => setState(() => _category = null),
                ),
                ...PasswordCategory.values.map(
                  (category) => _CategoryChip(
                    label: category.label,
                    selected: _category == category,
                    onTap: () => setState(() => _category = category),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.lock_outline,
                title: 'No passwords',
                subtitle: 'Add a credential or clear the current filter.',
              ),
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTileCard(
                  icon: item.isFavorite ? Icons.star : Icons.lock_outline,
                  title: item.title,
                  subtitle: '${item.username} · ${item.category.label}',
                  onTap: () => context.push(AppRoutes.passwordDetail(item.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class PasswordDetailScreen extends StatefulWidget {
  const PasswordDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<PasswordDetailScreen> createState() => _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends State<PasswordDetailScreen> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final item = state.passwords.where((entry) => entry.id == widget.id).firstOrNull;
    if (item == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Not found',
          subtitle: 'This password was removed.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.passwordEdit(item.id)),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () {
              state.deletePassword(item.id);
              showAppSnack(context, 'Password deleted');
              context.pop();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _InfoRow(label: 'Category', value: item.category.label),
          _InfoRow(
            label: 'Username',
            value: item.username,
            action: IconButton(
              onPressed: () => _copy(context, item.username, 'Username copied'),
              icon: const Icon(Icons.copy),
            ),
          ),
          _InfoRow(
            label: 'Password',
            value: _revealed ? item.password : '••••••••••••',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => setState(() => _revealed = !_revealed),
                  icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility),
                ),
                IconButton(
                  onPressed: () => _copy(context, item.password, 'Password copied'),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
          if (item.website.isNotEmpty)
            _InfoRow(
              label: 'Website',
              value: item.website,
              action: IconButton(
                onPressed: () => showAppSnack(context, 'Would open ${item.website}'),
                icon: const Icon(Icons.open_in_new),
              ),
            ),
          if (item.notes.isNotEmpty) _InfoRow(label: 'Notes', value: item.notes),
          _InfoRow(label: 'Tags', value: item.tags.join(', ')),
          _InfoRow(label: 'Updated', value: Formatters.date(item.updatedAt)),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showAppSnack(context, message);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.action,
  });

  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class PasswordFormScreen extends StatefulWidget {
  const PasswordFormScreen({super.key, this.id});

  final String? id;

  @override
  State<PasswordFormScreen> createState() => _PasswordFormScreenState();
}

class _PasswordFormScreenState extends State<PasswordFormScreen> {
  final _title = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _website = TextEditingController();
  final _notes = TextEditingController();
  PasswordCategory _category = PasswordCategory.other;
  bool _hydrated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated || widget.id == null) return;
    _hydrated = true;
    final existing = AppScope.of(
      context,
    ).passwords.where((item) => item.id == widget.id).firstOrNull;
    if (existing == null) return;
    _title.text = existing.title;
    _username.text = existing.username;
    _password.text = existing.password;
    _website.text = existing.website;
    _notes.text = existing.notes;
    _category = existing.category;
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _website.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.id != null;
    return FormPage(
      title: isEdit ? 'Edit password' : 'Add password',
      onSubmit: () => _save(AppScope.of(context)),
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _website,
          decoration: const InputDecoration(labelText: 'Website'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PasswordCategory>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: PasswordCategory.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
      ],
    );
  }

  void _save(AppState state) {
    if (_title.text.trim().isEmpty || _password.text.trim().isEmpty) {
      showAppSnack(context, 'Title and password are required');
      return;
    }
    if (widget.id == null) {
      state.addPassword(
        PasswordItem(
          id: state.nextId('pwd'),
          title: _title.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          website: _website.text.trim(),
          category: _category,
          notes: _notes.text.trim(),
          tags: const [],
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      final existing = state.passwords.firstWhere((item) => item.id == widget.id);
      state.updatePassword(
        existing.copyWith(
          title: _title.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          website: _website.text.trim(),
          category: _category,
          notes: _notes.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
    }
    showAppSnack(context, 'Password saved');
    context.pop();
  }
}

class PasswordGeneratorScreen extends StatefulWidget {
  const PasswordGeneratorScreen({super.key});

  @override
  State<PasswordGeneratorScreen> createState() => _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<PasswordGeneratorScreen> {
  double _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _excludeAmbiguous = true;
  String _generated = '';

  @override
  void initState() {
    super.initState();
    _generated = _generate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password generator')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SelectableText(
            _generated,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(_strengthLabel, style: TextStyle(color: _strengthColor)),
          const SizedBox(height: 16),
          Text('Length ${_length.round()}'),
          Slider(
            min: 8,
            max: 32,
            divisions: 24,
            value: _length,
            onChanged: (value) => setState(() {
              _length = value;
              _generated = _generate();
            }),
          ),
          SwitchListTile(
            title: const Text('Uppercase'),
            value: _upper,
            onChanged: (value) => _toggle(() => _upper = value),
          ),
          SwitchListTile(
            title: const Text('Lowercase'),
            value: _lower,
            onChanged: (value) => _toggle(() => _lower = value),
          ),
          SwitchListTile(
            title: const Text('Numbers'),
            value: _numbers,
            onChanged: (value) => _toggle(() => _numbers = value),
          ),
          SwitchListTile(
            title: const Text('Symbols'),
            value: _symbols,
            onChanged: (value) => _toggle(() => _symbols = value),
          ),
          SwitchListTile(
            title: const Text('Exclude ambiguous characters'),
            value: _excludeAmbiguous,
            onChanged: (value) => _toggle(() => _excludeAmbiguous = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() => _generated = _generate()),
            child: const Text('Generate'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _generated));
              if (!context.mounted) return;
              showAppSnack(context, 'Generated password copied');
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _toggle(VoidCallback update) {
    setState(() {
      update();
      _generated = _generate();
    });
  }

  String get _strengthLabel {
    if (_length >= 16 && _upper && _lower && _numbers && _symbols) return 'Strong';
    if (_length >= 12) return 'Medium';
    return 'Weak';
  }

  Color get _strengthColor {
    if (_strengthLabel == 'Strong') return AppColors.success;
    if (_strengthLabel == 'Medium') return AppColors.warning;
    return AppColors.danger;
  }

  String _generate() {
    var chars = '';
    if (_upper) chars += 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    if (_lower) chars += 'abcdefghijkmnopqrstuvwxyz';
    if (_numbers) chars += '23456789';
    if (_symbols) chars += '!@#\$%^&*()-_=+';
    if (!_excludeAmbiguous) {
      chars += 'Il1O0';
    }
    if (chars.isEmpty) chars = 'abcdefghijkmnopqrstuvwxyz';
    final buffer = StringBuffer();
    final now = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < _length.round(); i++) {
      buffer.write(chars[(now + i * 17) % chars.length]);
    }
    return buffer.toString();
  }
}
