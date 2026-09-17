import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/list_tile_card.dart';

class VaultHubScreen extends StatelessWidget {
  const VaultHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppPage(
      title: 'Vault',
      children: [
        ListTileCard(
          icon: Icons.lock_outline,
          title: 'Passwords',
          subtitle: state.vault.isUnlocked
              ? '${state.passwords.length} credentials'
              : state.vault.isSetup
                  ? 'Locked'
                  : 'Set up vault',
          onTap: () => context.push(AppRoutes.passwords),
          margin: AppDimensions.itemSpacing,
        ),
        ListTileCard(
          icon: Icons.description_outlined,
          title: 'Documents',
          subtitle: '${state.documents.length} files',
          onTap: () => context.push(AppRoutes.documents),
          margin: AppDimensions.itemSpacing,
        ),
        ListTileCard(
          icon: Icons.photo_outlined,
          title: 'Photos',
          subtitle: '${state.photos.length} items',
          onTap: () => context.push(AppRoutes.photos),
          margin: AppDimensions.itemSpacing,
        ),
        ListTileCard(
          icon: Icons.folder_outlined,
          title: 'Files',
          subtitle: '${state.files.length} items',
          onTap: () => context.push(AppRoutes.files),
          margin: AppDimensions.itemSpacing,
        ),
      ],
    );
  }
}
