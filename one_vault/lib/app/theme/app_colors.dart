import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const scaffold = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const iconWash = Color(0xFFEFF6FF);
  static const textMuted = Color(0xFF4B5563);
  static const border = Color(0xFFE5E7EB);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);

  static const darkScaffold = Color(0xFF0B1220);
  static const darkSurface = Color(0xFF162033);
  static const darkIconWash = Color(0xFF1E3A5F);
  static const darkMuted = Color(0xFF94A3B8);
  static const darkBorder = Color(0xFF334155);
  static const darkText = Color(0xFFF1F5F9);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color canvas(BuildContext context) =>
      isDark(context) ? darkScaffold : scaffold;

  static Color card(BuildContext context) =>
      isDark(context) ? darkSurface : surface;

  static Color line(BuildContext context) =>
      isDark(context) ? darkBorder : border;

  static Color muted(BuildContext context) =>
      isDark(context) ? darkMuted : textMuted;

  static Color wash(BuildContext context) =>
      isDark(context) ? darkIconWash : iconWash;
}
