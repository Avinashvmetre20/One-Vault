import 'package:flutter/material.dart';

import 'app_shell.dart';

class ShellFab extends StatelessWidget {
  const ShellFab({
    super.key,
    required this.onPressed,
    required this.heroTag,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final Object heroTag;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppShell.barClearance),
      child: FloatingActionButton(
        heroTag: heroTag,
        tooltip: tooltip ?? 'Add',
        onPressed: onPressed,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
