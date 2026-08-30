import 'package:flutter/material.dart';

import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../data/writeback/workout_writeback_coordinator.dart';
import '../../domain/writeback/workout_write_service.dart';
import 'workout_writeback_status.dart';

class WorkoutWritebackToggleCard extends StatefulWidget {
  const WorkoutWritebackToggleCard({super.key, required this.coordinator});

  final WorkoutWritebackCoordinator coordinator;

  @override
  State<WorkoutWritebackToggleCard> createState() =>
      _WorkoutWritebackToggleCardState();
}

class _WorkoutWritebackToggleCardState
    extends State<WorkoutWritebackToggleCard> {
  bool _busy = false;

  String _providerLabel({
    required WorkoutWriteCapability? capability,
    required TargetPlatform fallbackPlatform,
  }) {
    if (capability == null) {
      return healthPlatformLabel(platform: fallbackPlatform);
    }
    return switch (capability.platform) {
      WorkoutWritePlatform.iosHealthKit => 'Apple Health',
      WorkoutWritePlatform.androidHealthConnect => 'Health Connect',
      WorkoutWritePlatform.unsupported => 'Health',
    };
  }

  Future<void> _toggle(BuildContext context, bool enable) async {
    if (_busy) return;
    final fallbackPlatform = Theme.of(context).platform;
    setState(() {
      _busy = true;
    });
    try {
      await widget.coordinator.toggleEnabled(enable);
      final updated = widget.coordinator.state.value;
      if (enable && (!updated.enabled || !updated.permissionsGranted)) {
        if (!context.mounted) return;
        final provider = _providerLabel(
          capability: updated.capability,
          fallbackPlatform: fallbackPlatform,
        );
        HustlSnack.show(
          context,
          'Permission required: enable Workouts for Hustl in $provider to write workouts.',
          variant: HustlSnackVariant.warning,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<WorkoutWritebackState>(
      valueListenable: widget.coordinator.state,
      builder: (context, writeback, _) {
        final capability = writeback.capability;
        final capabilityKnown = capability != null;
        final supported = capability?.supported ?? false;
        final enabled = supported && writeback.enabled;
        final queueLen = writeback.queueLength;

        final provider = _providerLabel(
          capability: capability,
          fallbackPlatform: theme.platform,
        );
        final colorScheme = theme.colorScheme;
        final statusTone = workoutWritebackStatusTone(
          colorScheme: colorScheme,
          capabilityKnown: capabilityKnown,
          supported: supported,
          enabled: enabled,
          permissionsGranted: writeback.permissionsGranted,
          queueLen: queueLen,
        );

        String subtitle;
        if (!capabilityKnown) {
          subtitle = 'Checking support…';
        } else if (!supported) {
          subtitle = 'Not supported on this device';
        } else if (!enabled) {
          subtitle = 'Off · enable to write completed workouts to $provider';
        } else if (!writeback.permissionsGranted) {
          subtitle = 'Permissions missing · toggle to reconnect';
        } else if (queueLen > 0) {
          subtitle = 'Syncing $queueLen workout${queueLen == 1 ? '' : 's'}';
        } else {
          subtitle = 'On · writes completed workouts to $provider';
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: (!capabilityKnown || !supported || _busy)
                ? null
                : () => _toggle(context, !enabled),
            child: Ink(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [AppShadows.subtle(context)],
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 440;
                    final info = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: statusTone.background,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.sync_outlined,
                                color: statusTone.foreground,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Workout sync',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    provider,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!compact)
                              WorkoutWritebackStatusBadge(
                                label: workoutWritebackStatusLabel(
                                  capabilityKnown: capabilityKnown,
                                  supported: supported,
                                  enabled: enabled,
                                  permissionsGranted:
                                      writeback.permissionsGranted,
                                  queueLen: queueLen,
                                ),
                                tone: statusTone,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (compact) ...[
                          const SizedBox(height: AppSpacing.x2),
                          WorkoutWritebackStatusBadge(
                            label: workoutWritebackStatusLabel(
                              capabilityKnown: capabilityKnown,
                              supported: supported,
                              enabled: enabled,
                              permissionsGranted: writeback.permissionsGranted,
                              queueLen: queueLen,
                            ),
                            tone: statusTone,
                          ),
                        ],
                      ],
                    );

                    final toggle = Switch(
                      value: enabled,
                      onChanged: (!capabilityKnown || !supported || _busy)
                          ? null
                          : (value) => _toggle(context, value),
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          info,
                          const SizedBox(height: AppSpacing.x2),
                          Align(
                            alignment: Alignment.centerRight,
                            child: toggle,
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: info),
                        const SizedBox(width: AppSpacing.x2),
                        toggle,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
