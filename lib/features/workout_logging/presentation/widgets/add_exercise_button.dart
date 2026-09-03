import 'package:flutter/material.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

/// The add-exercise CTA — a flat themed FilledButton (interactive blue), no
/// shadow, no pill, sentence-case label. Button text inherits the labelLarge
/// row-value voice from the theme.
class AddExerciseButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isCompact;

  const AddExerciseButton({
    super.key,
    required this.onPressed,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    if (isCompact) {
      return SizedBox(
        height: 44,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: HustlIcon(
            asset: 'assets/icons/ic_add.svg',
            size: 18,
            color: onPrimary,
          ),
          label: const Text('Add'),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
      height: 44,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: HustlIcon(
          asset: 'assets/icons/ic_add.svg',
          size: 18,
          color: onPrimary,
        ),
        label: const Text('Add exercise'),
      ),
    );
  }
}
