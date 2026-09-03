import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  static BoxShadow subtle(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxShadow(
      color: AppColors.brandCarbonBlack.withValues(
        alpha: isLight ? 0.06 : 0.22,
      ),
      blurRadius: isLight ? 8 : 10,
      offset: const Offset(0, 2),
    );
  }

  static BoxShadow medium(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxShadow(
      color: AppColors.brandCarbonBlack.withValues(
        alpha: isLight ? 0.08 : 0.26,
      ),
      blurRadius: isLight ? 16 : 18,
      offset: const Offset(0, 4),
    );
  }

  static BoxShadow strong(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxShadow(
      color: AppColors.brandCarbonBlack.withValues(alpha: isLight ? 0.12 : 0.3),
      blurRadius: isLight ? 24 : 28,
      offset: const Offset(0, 8),
    );
  }

  static List<BoxShadow> lifted(BuildContext context) {
    return [subtle(context), medium(context)];
  }
}
