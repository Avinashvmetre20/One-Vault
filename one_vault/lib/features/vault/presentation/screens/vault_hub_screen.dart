import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/list_tile_card.dart';

class VaultHubScreen extends StatefulWidget {
  const VaultHubScreen({super.key});

  @override
  State<VaultHubScreen> createState() => _VaultHubScreenState();
}

class _VaultHubScreenState extends State<VaultHubScreen> {
  static const _vaultTab = 1;
  ValueNotifier<int>? _shellIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final index = AppScope.of(context).shellTabIndex;
    if (!identical(_shellIndex, index)) {
      _shellIndex?.removeListener(_onShellTab);
      _shellIndex = index;
      _shellIndex!.addListener(_onShellTab);
    }
    _onShellTab();
  }

  void _onShellTab() {
    if (!mounted || _shellIndex?.value != _vaultTab) return;
    unawaited(AppScope.of(context).vault.bind());
  }

  @override
  void dispose() {
    _shellIndex?.removeListener(_onShellTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppPage(
      title: 'Vault',
      refresh: state.vault.refreshHub,
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
