import 'package:flutter/material.dart';

/// Overlays a thin top progress line on [child] while [refreshing].
///
/// Used by the nutrition analytics screens for stale-while-revalidate: cached
/// content paints instantly and this quiet line signals a background refresh,
/// instead of a full blocking skeleton on every visit.
class RefreshLineOverlay extends StatelessWidget {
  const RefreshLineOverlay({
    super.key,
    required this.refreshing,
    required this.child,
  });

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}
