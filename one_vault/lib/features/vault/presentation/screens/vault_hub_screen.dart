import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/hub_card.dart';

class VaultHubScreen extends StatelessWidget {
  const VaultHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          HubCard(
            icon: Icons.lock_outline,
            title: 'Passwords',
            subtitle: state.vault.isUnlocked
                ? '${state.passwords.length} credentials'
                : state.vault.isSetup
                    ? 'Locked'
                    : 'Set up vault',
            onTap: () => context.push(AppRoutes.passwords),
          ),
          HubCard(
            icon: Icons.description_outlined,
            title: 'Documents',
            subtitle: '${state.documents.length} files',
            onTap: () => context.push(AppRoutes.documents),
          ),
          HubCard(
            icon: Icons.photo_outlined,
            title: 'Photos',
            subtitle: '${state.photos.length} items',
            onTap: () => context.push(AppRoutes.photos),
          ),
          HubCard(
            icon: Icons.folder_outlined,
            title: 'Files',
            subtitle: '${state.files.length} items',
            onTap: () => context.push(AppRoutes.files),
          ),
        ],
      ),
    );
  }
}
