import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Text(label, style: const TextStyle(fontWeight: FontWeight.w700));
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      ),
    );
    if (icon == null || loading) {
      return FilledButton(
        onPressed: loading ? null : onPressed,
        style: style,
        child: child,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon),
      label: child,
    );
  }
}
