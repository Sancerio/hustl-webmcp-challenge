import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';

/// The single drag-handle used at the top of every bottom sheet, so all modal
/// grabbers match exactly (36×4, pill radius, [ColorScheme.outlineVariant]).
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: AppRadius.pillRadius,
        ),
      ),
    );
  }
}
