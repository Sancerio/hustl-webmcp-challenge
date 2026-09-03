import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_skeleton.dart';

class ActiveWorkoutSkeleton extends StatelessWidget {
  const ActiveWorkoutSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screen,
      child: ListView(
        children: const [
          AppSkeleton(width: double.infinity, height: 56),
          SizedBox(height: AppSpacing.x2),
          AppSkeleton(
            width: double.infinity,
            height: 180,
            borderRadius: AppRadius.cardRadius,
          ),
          SizedBox(height: AppSpacing.x2),
          AppSkeleton(
            width: double.infinity,
            height: 180,
            borderRadius: AppRadius.cardRadius,
          ),
          SizedBox(height: AppSpacing.x2),
          AppSkeleton(width: double.infinity, height: 48),
        ],
      ),
    );
  }
}
