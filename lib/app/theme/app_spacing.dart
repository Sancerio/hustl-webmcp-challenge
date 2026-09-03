import 'package:flutter/widgets.dart';

/// 8pt spacing scale used across layout, cards, and section rhythm.
class AppSpacing {
  AppSpacing._();

  static const double x1 = 8;
  static const double x2 = 16;
  static const double x3 = 24;
  static const double x4 = 32;
  static const double x5 = 40;
  static const double x6 = 48;

  static const EdgeInsets screen = EdgeInsets.all(x2);
  static const EdgeInsets cardPadding = EdgeInsets.all(x2);
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: x2,
    vertical: x3,
  );
}
