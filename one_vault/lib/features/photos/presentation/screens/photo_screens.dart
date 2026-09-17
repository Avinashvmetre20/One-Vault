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

class PhotoListScreen extends StatelessWidget {
  const PhotoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final photos = AppScope.of(context).photos;
    final albums = photos.map((item) => item.album).toSet().toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-photos',
        tooltip: 'Add photo',
        onPressed: () => context.push(AppRoutes.photoNew),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
        children: [
          Text('Albums', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: albums
                .map((album) => Chip(label: Text(album)))
                .toList(),
          ),
          const SizedBox(height: 16),
          if (photos.isEmpty)
            const EmptyState(
              icon: Icons.photo_outlined,
              title: 'No photos',
              subtitle: 'Add a photo placeholder to this album.',
            )
          else
            ...photos.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTileCard(
                  icon: item.isPrivate ? Icons.lock_outline : Icons.photo_outlined,
                  title: item.name,
                  subtitle:
                      '${item.album} · ${item.sizeLabel} · ${Formatters.date(item.createdAt)}',
                  onTap: () => context.push(AppRoutes.photoDetail(item.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PhotoDetailScreen extends StatelessWidget {
  const PhotoDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final item = AppScope.of(context).photos.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.photo_outlined,
          title: 'Not found',
          subtitle: 'This photo is not in the vault.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.photo, size: 72, color: Color(0xFF2563EB)),
          ),
          const SizedBox(height: 20),
          Text('Album: ${item.album}'),
          const SizedBox(height: 8),
          Text('Size: ${item.sizeLabel}'),
          const SizedBox(height: 8),
          Text('Taken: ${Formatters.date(item.createdAt)}'),
          const SizedBox(height: 8),
          Text(item.isPrivate ? 'Private photo' : 'Visible in album'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => showAppSnack(context, 'Image viewer will be added later'),
            child: const Text('Open viewer'),
          ),
        ],
      ),
    );
  }
}

class PhotoFormScreen extends StatefulWidget {
  const PhotoFormScreen({super.key});

  @override
  State<PhotoFormScreen> createState() => _PhotoFormScreenState();
}

class _PhotoFormScreenState extends State<PhotoFormScreen> {
  final _name = TextEditingController();
  final _album = TextEditingController(text: 'Personal');

  @override
  void dispose() {
    _name.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add photo',
      onSubmit: () {
        if (_name.text.trim().isEmpty) {
          showAppSnack(context, 'Name is required');
          return;
        }
        final state = AppScope.of(context);
        state.addPhoto(
          PhotoItem(
            id: state.nextId('photo'),
            name: _name.text.trim(),
            album: _album.text.trim().isEmpty ? 'Personal' : _album.text.trim(),
            createdAt: DateTime.now(),
            sizeLabel: '2.0 MB',
          ),
        );
        showAppSnack(context, 'Photo added');
        context.pop();
      },
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Photo name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _album,
          decoration: const InputDecoration(labelText: 'Album'),
        ),
      ],
    );
  }
}
