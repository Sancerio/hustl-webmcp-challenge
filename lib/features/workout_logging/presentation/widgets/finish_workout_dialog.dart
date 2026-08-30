import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'hustl_dialog.dart';

class FinishWorkoutDialog extends StatelessWidget {
  const FinishWorkoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HustlDialog(
      celebration: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.95, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Icon(
            Icons.check_circle_rounded,
            size: 48,
            color: theme.colorScheme.tertiary,
          ),
        ),
      ),
      title: 'Finish Workout?',
      content:
          "Are you sure you want to finish this workout? You can't add more sets or exercises after finishing.",
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => context.pop(true),
          child: const Text('Finish'),
        ),
      ],
    );
  }
}
