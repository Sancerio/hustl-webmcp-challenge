import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../health_sync/domain/models/daily_recovery_snapshot.dart';
import '../../../health_sync/domain/usecases/recovery_flow_copy.dart';
import '../../../health_sync/presentation/widgets/dashboard/recovery_band_tint.dart';
import '../../domain/services/rest_timer_service.dart';

class GlobalTimerDialog extends StatefulWidget {
  final RestTimerService restTimerService;
  final Function(int) onStartTimer;
  final VoidCallback onClose;

  /// Optional, low-readiness recovery snapshot. When present AND
  /// [RecoveryFlowCopy.shouldSuggestMoreRest] is true, the dialog surfaces a
  /// single quiet, dismissible "consider a bit more rest" line with a one-tap
  /// "+30s" accept. Null (the default) → the dialog is exactly as today.
  final DailyRecoverySnapshot? recoverySnapshot;

  /// Called once when the user accepts or dismisses the suggestion, so the
  /// owner can flip its once-per-session flag and never offer it again.
  final VoidCallback? onSuggestionResolved;

  const GlobalTimerDialog({
    super.key,
    required this.restTimerService,
    required this.onStartTimer,
    required this.onClose,
    this.recoverySnapshot,
    this.onSuggestionResolved,
  });

  @override
  State<GlobalTimerDialog> createState() => _GlobalTimerDialogState();
}

class _GlobalTimerDialogState extends State<GlobalTimerDialog> {
  int _selectedSeconds = RestTimerService.defaultRestTime;
  late bool _showSuggestion;

  // Preset timer durations in seconds
  final List<int> _presetDurations = [30, 60, 90, 120, 180, 300];

  @override
  void initState() {
    super.initState();
    _showSuggestion = RecoveryFlowCopy.shouldSuggestMoreRest(
      widget.recoverySnapshot,
    );
  }

  /// One-tap accept: bump the suggested rest by +30s (clamped to the slider
  /// range) and resolve the suggestion so it never reappears this session. This
  /// only changes the SUGGESTED default the user is about to start — never the
  /// timer silently.
  void _acceptSuggestion() {
    setState(() {
      _selectedSeconds = (_selectedSeconds + RecoveryFlowCopy.restBumpSeconds)
          .clamp(5, 600);
      _showSuggestion = false;
    });
    widget.onSuggestionResolved?.call();
  }

  void _dismissSuggestion() {
    setState(() => _showSuggestion = false);
    widget.onSuggestionResolved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rest timer',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
          if (_showSuggestion) ...[
            const SizedBox(height: AppSpacing.x2),
            _RestSuggestionLine(
              snapshot: widget.recoverySnapshot,
              onAccept: _acceptSuggestion,
              onDismiss: _dismissSuggestion,
            ),
          ],
          const SizedBox(height: 16),

          // Timer display
          Text(
            RestTimerService.formatTime(_selectedSeconds),
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),

          // Preset durations
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _presetDurations.map((seconds) {
              final isSelected = _selectedSeconds == seconds;
              final formattedTime = RestTimerService.formatTime(seconds);

              return ChoiceChip(
                label: Text(formattedTime),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedSeconds = seconds;
                    });
                  }
                },
                selectedColor: theme.colorScheme.primary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Custom duration slider
          Slider(
            value: _selectedSeconds.toDouble(),
            min: 5,
            max: 600, // 10 minutes max
            divisions: 595, // increments of 1 second
            label: RestTimerService.formatTime(_selectedSeconds),
            onChanged: (value) {
              setState(() {
                _selectedSeconds = value.round();
              });
            },
            activeColor: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),

          // Start button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onStartTimer(_selectedSeconds),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Timer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single quiet, band-tinted, dismissible readiness suggestion line. Color
/// is paired with text (color-blind safe); the tint comes from the domain's
/// band → token mapping (warm amber for low, never red). One-tap "+30s" accept,
/// or a dismiss "x" — both resolve the suggestion for the rest of the session.
class _RestSuggestionLine extends StatelessWidget {
  const _RestSuggestionLine({
    required this.snapshot,
    required this.onAccept,
    required this.onDismiss,
  });

  final DailyRecoverySnapshot? snapshot;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bandColors = RecoveryBandColors.resolve(colors, snapshot?.flowBand);

    return Semantics(
      container: true,
      label:
          '${RecoveryFlowCopy.restSuggestionLine} '
          '${RecoveryFlowCopy.restSuggestionAction()}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          AppSpacing.x1,
          AppSpacing.x1,
          AppSpacing.x1,
        ),
        decoration: BoxDecoration(
          color: bandColors.container,
          borderRadius: AppRadius.controlRadius,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                RecoveryFlowCopy.restSuggestionLine,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            TextButton(
              onPressed: onAccept,
              style: TextButton.styleFrom(
                foregroundColor: bandColors.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x1 + 4,
                ),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(RecoveryFlowCopy.restSuggestionAction()),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: colors.onSurfaceVariant),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
