import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';

class FileListScreen extends StatelessWidget {
  const FileListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    return AppPage(
      title: 'Files',
      fab: ShellFab(
        heroTag: 'fab-files',
        tooltip: 'Add file',
        onPressed: () => context.push(AppRoutes.fileNew),
      ),
      children: [
        if (files.isEmpty)
          const EmptyState(
            icon: Icons.folder_outlined,
            title: 'No files',
            subtitle: 'Create a file record to see it here.',
          )
        else
          ...files.map(
            (item) => ListTileCard(
              icon: Icons.insert_drive_file_outlined,
              title: item.name,
              subtitle:
                  '${item.folder} · ${item.fileType} · ${item.sizeLabel} · ${Formatters.date(item.createdAt)}',
              onTap: () => context.push(AppRoutes.fileDetail(item.id)),
              margin: AppDimensions.itemSpacing,
            ),
          ),
      ],
    );
  }
}

class FileDetailScreen extends StatelessWidget {
  const FileDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final item = AppScope.of(context).files.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return const AppMissingPage(
        icon: Icons.folder_outlined,
        title: 'Not found',
        subtitle: 'This file is not in the vault.',
      );
    }

    return AppDetailPage(
      title: item.name,
      children: [
        InfoRow(label: 'Folder', value: item.folder),
        InfoRow(label: 'Type', value: item.fileType),
        InfoRow(label: 'Size', value: item.sizeLabel),
        InfoRow(label: 'Created', value: Formatters.date(item.createdAt)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => showAppSnack(context, 'File preview will be added later'),
          child: const Text('Preview'),
        ),
      ],
    );
  }
}

class FileFormScreen extends StatefulWidget {
  const FileFormScreen({super.key});

  @override
  State<FileFormScreen> createState() => _FileFormScreenState();
}

class _FileFormScreenState extends State<FileFormScreen> {
  final _name = TextEditingController();
  final _folder = TextEditingController(text: 'Personal');
  String _type = 'PDF';

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add file',
      onSubmit: () {
        if (_name.text.trim().isEmpty) {
          showAppSnack(context, 'Name is required');
          return;
        }
        final state = AppScope.of(context);
        state.addFile(
          FileItem(
            id: state.nextId('file'),
            name: _name.text.trim(),
            folder: _folder.text.trim().isEmpty ? 'Personal' : _folder.text.trim(),
            fileType: _type,
            sizeLabel: '250 KB',
            createdAt: DateTime.now(),
          ),
        );
        showAppSnack(context, 'File added');
        context.pop();
      },
      children: [
        AppTextField(controller: _name, label: 'File name'),
        AppDimensions.fieldGap,
        AppTextField(controller: _folder, label: 'Folder'),
        AppDimensions.fieldGap,
        AppDropdown<String>(
          label: 'Type',
          value: _type,
          items: const ['PDF', 'DOC', 'DOCX', 'XLS', 'XLSX', 'TXT', 'JPG', 'PNG', 'ZIP', 'CSV']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
      ],
    );
  }
}
