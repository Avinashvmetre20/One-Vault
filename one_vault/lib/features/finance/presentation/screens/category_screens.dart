import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/finance_models.dart';
import '../../data/finance_service.dart';
import '../widgets/money_widgets.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<MoneyCategory> _items = [];
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
      final items = await _api.categories();
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

  Future<void> _add() async {
    final name = TextEditingController();
    var kind = CategoryKind.expense;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: name, label: 'Name'),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setLocal) {
                  return AppDropdown<CategoryKind>(
                    label: 'Type',
                    value: kind,
                    items: CategoryKind.values
                        .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                        .toList(),
                    onChanged: (value) => setLocal(() => kind = value ?? kind),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        );
      },
    );
    if (saved != true || name.text.trim().isEmpty) return;
    try {
      await _api.createCategory(name.text.trim(), kind.api);
      if (mounted) _load();
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-categories',
        tooltip: 'Add category',
        onPressed: _add,
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
              const EmptyState(
                icon: Icons.category_outlined,
                title: 'No categories',
                subtitle: 'Categories are created automatically. Pull to refresh.',
              )
            else
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTileCard(
                    icon: Icons.category_outlined,
                    title: item.name,
                    subtitle: item.kind.label,
                    trailing: item.isSystem
                        ? Text('Default', style: TextStyle(color: AppColors.muted(context), fontSize: 12))
                        : IconButton(
                            onPressed: () async {
                              final confirmed = await showAppConfirm(
                                context,
                                title: 'Delete category?',
                                message: '${item.name} will be removed.',
                              );
                              if (!confirmed || !mounted) return;
                              try {
                                await _api.deleteCategory(item.id);
                                if (mounted) _load();
                              } catch (error) {
                                if (mounted) showAppSnack(context, error.toString());
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
