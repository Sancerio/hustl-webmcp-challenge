import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';

/// Per-card loading skeleton for the Progress screen — reserves the hero + card
/// heights so the layout holds and each block fills in place, instead of a lone
/// generic line group that pops and reflows on load.
class ProgressSkeleton extends StatelessWidget {
  const ProgressSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    // Scrollable so it can never overflow a short/landscape viewport (the loaded
    // content is a ListView too), and padded to match the loaded layout so each
    // placeholder sits where its real card lands.
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x4,
      ),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        AppSkeleton(
          height: 184,
          borderRadius: radius,
        ), // consistency + volume hero
        const SizedBox(height: AppSpacing.x3),
        AppSkeleton(height: 132, borderRadius: radius), // training balance card
        const SizedBox(height: AppSpacing.x3),
        AppSkeleton(
          height: 220,
          borderRadius: radius,
        ), // volume-over-time chart
        const SizedBox(height: AppSpacing.x3),
        AppSkeleton(height: 168, borderRadius: radius), // strength (e1RM) card
      ],
    );
  }
}
