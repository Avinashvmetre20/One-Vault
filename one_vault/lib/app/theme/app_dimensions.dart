import 'package:flutter/material.dart';

abstract final class AppDimensions {
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 18.0;
  static const radiusXl = 24.0;
  static const gridSpacing = 14.0;
  static const minActionCardHeight = 132.0;
  static const iconBox = 44.0;
  static const buttonHeight = 52.0;

  static const pagePadding = EdgeInsets.fromLTRB(20, 8, 20, 32);
  static const pagePaddingFab = EdgeInsets.fromLTRB(20, 8, 20, 88);
  static const pagePaddingTallFab = EdgeInsets.fromLTRB(20, 8, 20, 160);
  static const pagePaddingForm = EdgeInsets.fromLTRB(20, 12, 20, 32);
  static const pagePaddingAuth = EdgeInsets.fromLTRB(20, 24, 20, 32);
  static const itemSpacing = EdgeInsets.only(bottom: 12);
  static const fieldGap = SizedBox(height: 12);
  static const sectionGap = SizedBox(height: 16);

  static double horizontalPadding(double width) {
    if (width < 360) return 16;
    if (width < 600) return 20;
    return 24;
  }
}
