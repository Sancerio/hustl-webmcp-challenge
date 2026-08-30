import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

import '../../domain/models/nutrition_target_plan.dart';

/// The single "Adjusting your plan" control surface — the one place the coached
/// behaviour is configured. Absorbs the old toggle + lock rows + header actions.
class StrategyControlsCard extends StatelessWidget {
  const StrategyControlsCard({
    super.key,
    required this.plan,
    required this.onToggleMode,
    required this.onSetLock,
    required this.onClearLock,
    required this.onEditTargets,
    required this.onSetGoal,
    required this.momentumEnabled,
    required this.onToggleMomentum,
    required this.coachExplainsEnabled,
    required this.onToggleCoachExplains,
  });

  final NutritionTargetPlan plan;
  final ValueChanged<bool> onToggleMode;
  final VoidCallback onSetLock;
  final VoidCallback onClearLock;
  final VoidCallback onEditTargets;
  final VoidCallback onSetGoal;

  /// Opt-in behavioral-momentum coach tips (item 4) + its toggle handler.
  final bool momentumEnabled;
  final ValueChanged<bool> onToggleMomentum;

  /// Opt-in "Coach explains my numbers" narrative (item 6) + its toggle handler.
  final bool coachExplainsEnabled;
  final ValueChanged<bool> onToggleCoachExplains;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    final isAuto = plan.mode == 'auto';
    final nextCheckIn = plan.weekStart.add(const Duration(days: 7));
    final locked = plan.lockedUntil;
    final isLocked = locked != null && locked.isAfter(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Adjusting your plan'),
        SectionList(
          card: true,
          children: [
            CoachToggleRow(value: isAuto, onChanged: onToggleMode),
            if (isAuto)
              _ControlRow(
                label: 'Next check-in',
                value: fmt.format(nextCheckIn),
              ),
            _PauseRow(
              valueLabel: isLocked
                  ? 'Until ${fmt.format(locked.toLocal())}'
                  : 'Off',
              caption: 'Useful while travelling or on a diet break.',
              actionLabel: isLocked ? 'Resume now' : 'Pause…',
              onAction: isLocked ? onClearLock : onSetLock,
            ),
            MomentumToggleRow(
              value: momentumEnabled,
              onChanged: onToggleMomentum,
            ),
            CoachExplainsToggleRow(
              value: coachExplainsEnabled,
              onChanged: onToggleCoachExplains,
            ),
            if ((plan.rationale ?? '').trim().isNotEmpty)
              _WhyExpansion(rationale: plan.rationale!),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onEditTargets,
                child: const Text('Edit targets'),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: OutlinedButton(
                onPressed: onSetGoal,
                child: const Text('Set goal'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The one consequential control: whether targets adapt with the weekly
/// check-in. A weighted title + a stakes caption that switches on state.
class CoachToggleRow extends StatelessWidget {
  const CoachToggleRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adapt targets weekly',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'On — targets follow your weekly check-in.'
                      : 'Off — targets stay where you set them.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Opt-in toggle for the multi-week behavioral-momentum coach tips (item 4). Off
/// by default; turning it on lets the Insights coach respond to streaks and
/// slips, not just thresholds.
class MomentumToggleRow extends StatelessWidget {
  const MomentumToggleRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Momentum tips',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'On — coach reacts to your multi-week streaks.'
                      : 'Off — coach sticks to your current trends.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Opt-in toggle for the "Coach explains my numbers" LLM narrative (item 6). Off
/// by default and independent of momentum. Even when on it stays a no-op unless
/// the backend feature flag is enabled, so the Insights coach is never noisy.
class CoachExplainsToggleRow extends StatelessWidget {
  const CoachExplainsToggleRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Coach explains my numbers',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'On — a short plain-language note above your tips.'
                      : 'Off — your coach tips stand on their own.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Text(value, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _PauseRow extends StatelessWidget {
  const _PauseRow({
    required this.valueLabel,
    required this.caption,
    required this.actionLabel,
    required this.onAction,
  });

  final String valueLabel;
  final String caption;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pause adjustments',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Text(valueLabel, style: theme.textTheme.labelLarge),
              const SizedBox(width: 4),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhyExpansion extends StatelessWidget {
  const _WhyExpansion({required this.rationale});

  final String rationale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        title: Text(
          'Why did targets change?',
          style: theme.textTheme.bodyLarge,
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              rationale,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
