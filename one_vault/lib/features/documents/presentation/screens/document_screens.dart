import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/app_filter_chips.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  String _query = '';
  DocumentCategory? _category;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.documents.where((item) {
      final matchesQuery =
          _query.isEmpty || item.name.toLowerCase().contains(_query.toLowerCase());
      final matchesCategory = _category == null || item.category == _category;
      return matchesQuery && matchesCategory;
    }).toList();

    return AppPage(
      title: 'Documents',
      fab: ShellFab(
        heroTag: 'fab-documents',
        tooltip: 'Add document',
        onPressed: () => context.push(AppRoutes.documentNew),
      ),
      children: [
        AppSearchField(
          hintText: 'Search documents',
          onChanged: (value) => setState(() => _query = value),
        ),
        AppDimensions.fieldGap,
        AppFilterChips<DocumentCategory>(
          value: _category,
          options: DocumentCategory.values,
          labelOf: (category) => category.label,
          onChanged: (value) => setState(() => _category = value),
        ),
        AppDimensions.sectionGap,
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: EmptyState(
              icon: Icons.description_outlined,
              title: 'No documents',
              subtitle: 'Add a file or choose another category.',
            ),
          )
        else
          ...items.map(
            (item) => ListTileCard(
              icon: Icons.description_outlined,
              title: item.name,
              subtitle:
                  '${item.category.label} · ${item.sizeLabel}${item.expiryDate == null ? '' : ' · Expires ${Formatters.date(item.expiryDate!)}'}',
              onTap: () => context.push(AppRoutes.documentDetail(item.id)),
              margin: AppDimensions.itemSpacing,
            ),
          ),
      ],
    );
  }
}

class DocumentDetailScreen extends StatelessWidget {
  const DocumentDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final item = AppScope.of(context).documents.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return const AppMissingPage(
        icon: Icons.description_outlined,
        title: 'Not found',
        subtitle: 'This document is not in the vault.',
      );
    }

    return AppDetailPage(
      title: item.name,
      children: [
        InfoRow(label: 'Category', value: item.category.label),
        InfoRow(label: 'Type', value: item.fileType),
        InfoRow(label: 'Size', value: item.sizeLabel),
        InfoRow(label: 'Created', value: Formatters.date(item.createdAt)),
        InfoRow(
          label: 'Expiry',
          value: item.expiryDate == null ? 'None' : Formatters.date(item.expiryDate!),
        ),
        InfoRow(label: 'Tags', value: item.tags.join(', ')),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showAppSnack(context, 'PDF viewer will be added later'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open viewer'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showAppSnack(context, 'Share is not wired yet'),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
      ],
    );
  }
}

class DocumentFormScreen extends StatefulWidget {
  const DocumentFormScreen({super.key});

  @override
  State<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<DocumentFormScreen> {
  final _name = TextEditingController();
  DocumentCategory _category = DocumentCategory.other;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add document',
      onSubmit: () {
        if (_name.text.trim().isEmpty) {
          showAppSnack(context, 'Name is required');
          return;
        }
        final state = AppScope.of(context);
        state.addDocument(
          DocumentItem(
            id: state.nextId('doc'),
            name: _name.text.trim(),
            category: _category,
            fileType: 'PDF',
            sizeLabel: '1.0 MB',
            createdAt: DateTime.now(),
            tags: const [],
          ),
        );
        showAppSnack(context, 'Document added');
        context.pop();
      },
      children: [
        AppTextField(controller: _name, label: 'File name'),
        AppDimensions.fieldGap,
        AppDropdown<DocumentCategory>(
          label: 'Category',
          value: _category,
          items: DocumentCategory.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
      ],
    );
  }
}
