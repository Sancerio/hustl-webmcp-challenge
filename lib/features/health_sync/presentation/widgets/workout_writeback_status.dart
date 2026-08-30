import 'package:flutter/material.dart';

class WorkoutWritebackStatusTone {
  const WorkoutWritebackStatusTone({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

WorkoutWritebackStatusTone workoutWritebackStatusTone({
  required ColorScheme colorScheme,
  required bool capabilityKnown,
  required bool supported,
  required bool enabled,
  required bool permissionsGranted,
  required int queueLen,
}) {
  if (!capabilityKnown) {
    return WorkoutWritebackStatusTone(
      background: colorScheme.primaryContainer,
      foreground: colorScheme.onPrimaryContainer,
    );
  }
  if (!supported || !permissionsGranted) {
    return WorkoutWritebackStatusTone(
      background: colorScheme.errorContainer,
      foreground: colorScheme.onErrorContainer,
    );
  }
  if (enabled && queueLen > 0) {
    return WorkoutWritebackStatusTone(
      background: colorScheme.tertiaryContainer,
      foreground: colorScheme.onTertiaryContainer,
    );
  }
  if (enabled) {
    return WorkoutWritebackStatusTone(
      background: colorScheme.secondaryContainer,
      foreground: colorScheme.onSecondaryContainer,
    );
  }
  return WorkoutWritebackStatusTone(
    background: colorScheme.surfaceContainerHigh,
    foreground: colorScheme.onSurfaceVariant,
  );
}

String workoutWritebackStatusLabel({
  required bool capabilityKnown,
  required bool supported,
  required bool enabled,
  required bool permissionsGranted,
  required int queueLen,
}) {
  if (!capabilityKnown) return 'Checking';
  if (!supported) return 'Unavailable';
  if (!permissionsGranted) return 'Needs access';
  if (enabled && queueLen > 0) return 'Syncing $queueLen';
  if (enabled) return 'Live';
  return 'Off';
}

class WorkoutWritebackStatusBadge extends StatelessWidget {
  const WorkoutWritebackStatusBadge({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final WorkoutWritebackStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: tone.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
