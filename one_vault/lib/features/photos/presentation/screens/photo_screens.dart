import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
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

class PhotoListScreen extends StatelessWidget {
  const PhotoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final photos = AppScope.of(context).photos;
    final albums = photos.map((item) => item.album).toSet().toList();

    return AppPage(
      title: 'Photos',
      fab: ShellFab(
        heroTag: 'fab-photos',
        tooltip: 'Add photo',
        onPressed: () => context.push(AppRoutes.photoNew),
      ),
      children: [
        Text('Albums', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: albums.map((album) => Chip(label: Text(album))).toList(),
        ),
        AppDimensions.sectionGap,
        if (photos.isEmpty)
          const EmptyState(
            icon: Icons.photo_outlined,
            title: 'No photos',
            subtitle: 'Add a photo placeholder to this album.',
          )
        else
          ...photos.map(
            (item) => ListTileCard(
              icon: item.isPrivate ? Icons.lock_outline : Icons.photo_outlined,
              title: item.name,
              subtitle: '${item.album} · ${item.sizeLabel} · ${Formatters.date(item.createdAt)}',
              onTap: () => context.push(AppRoutes.photoDetail(item.id)),
              margin: AppDimensions.itemSpacing,
            ),
          ),
      ],
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
      return const AppMissingPage(
        icon: Icons.photo_outlined,
        title: 'Not found',
        subtitle: 'This photo is not in the vault.',
      );
    }

    return AppDetailPage(
      title: item.name,
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.wash(context),
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
          child: const Icon(Icons.photo, size: 72, color: AppColors.primary),
        ),
        const SizedBox(height: 20),
        InfoRow(label: 'Album', value: item.album),
        InfoRow(label: 'Size', value: item.sizeLabel),
        InfoRow(label: 'Taken', value: Formatters.date(item.createdAt)),
        InfoRow(label: 'Visibility', value: item.isPrivate ? 'Private photo' : 'Visible in album'),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => showAppSnack(context, 'Image viewer will be added later'),
          child: const Text('Open viewer'),
        ),
      ],
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
        AppTextField(controller: _name, label: 'Photo name'),
        AppDimensions.fieldGap,
        AppTextField(controller: _album, label: 'Album'),
      ],
    );
  }
}
