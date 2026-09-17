import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-files',
        tooltip: 'Add file',
        onPressed: () => context.push(AppRoutes.fileNew),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          if (files.isEmpty)
            const EmptyState(
              icon: Icons.folder_outlined,
              title: 'No files',
              subtitle: 'Create a file record to see it here.',
            )
          else
            ...files.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTileCard(
                  icon: Icons.insert_drive_file_outlined,
                  title: item.name,
                  subtitle:
                      '${item.folder} · ${item.fileType} · ${item.sizeLabel} · ${Formatters.date(item.createdAt)}',
                  onTap: () => context.push(AppRoutes.fileDetail(item.id)),
                ),
              ),
            ),
        ],
      ),
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
      return const Scaffold(
        body: EmptyState(
          icon: Icons.folder_outlined,
          title: 'Not found',
          subtitle: 'This file is not in the vault.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Folder: ${item.folder}'),
          const SizedBox(height: 8),
          Text('Type: ${item.fileType}'),
          const SizedBox(height: 8),
          Text('Size: ${item.sizeLabel}'),
          const SizedBox(height: 8),
          Text('Created: ${Formatters.date(item.createdAt)}'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => showAppSnack(context, 'File preview will be added later'),
            child: const Text('Preview'),
          ),
        ],
      ),
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
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'File name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _folder,
          decoration: const InputDecoration(labelText: 'Folder'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const ['PDF', 'DOC', 'DOCX', 'XLS', 'XLSX', 'TXT', 'JPG', 'PNG', 'ZIP', 'CSV']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
      ],
    );
  }
}
