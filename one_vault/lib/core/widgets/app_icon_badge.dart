import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.size = AppDimensions.iconBox,
    this.iconSize,
  });

  final IconData icon;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.wash(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Icon(icon, color: AppColors.primary, size: iconSize),
    );
  }
}
