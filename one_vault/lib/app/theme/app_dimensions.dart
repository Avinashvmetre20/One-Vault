abstract final class AppDimensions {
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 18.0;
  static const radiusXl = 24.0;
  static const pagePadding = 20.0;
  static const gridSpacing = 14.0;
  static const minActionCardHeight = 132.0;

  static double horizontalPadding(double width) {
    if (width < 360) return 16;
    if (width < 600) return 20;
    return 24;
  }
}
