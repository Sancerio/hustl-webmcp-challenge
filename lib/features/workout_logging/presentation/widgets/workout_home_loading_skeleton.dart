import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_skeleton.dart';

/// Mirrors the Train dashboard shape while it hydrates: week training widget,
/// next-session row, then flat section rows.
class WorkoutHomeLoadingSkeleton extends StatelessWidget {
  const WorkoutHomeLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSkeleton(width: double.infinity, height: 56, animate: false),
        SizedBox(height: AppSpacing.x3),
        AppSkeleton(width: double.infinity, height: 48, animate: false),
        SizedBox(height: AppSpacing.x3),
        AppSkeleton(width: 96, height: 16, animate: false),
        SizedBox(height: AppSpacing.x2),
        AppSkeleton(width: double.infinity, height: 44, animate: false),
        SizedBox(height: AppSpacing.x1),
        AppSkeleton(width: double.infinity, height: 44, animate: false),
        SizedBox(height: AppSpacing.x3),
        AppSkeleton(width: 96, height: 16, animate: false),
        SizedBox(height: AppSpacing.x2),
        AppSkeleton(width: double.infinity, height: 40, animate: false),
        SizedBox(height: AppSpacing.x1),
        AppSkeleton(width: double.infinity, height: 40, animate: false),
        SizedBox(height: AppSpacing.x1),
        AppSkeleton(width: double.infinity, height: 40, animate: false),
      ],
    );
  }
}
