import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';

import '../../domain/models/workout_set.dart';
import 'set_row_layout.dart';

class SetRowContent extends StatelessWidget {
  final int setIndex;

  /// 1-based working-set ordinal, re-derived over non-warm-up sets only, so a
  /// card with two warm-ups + three work sets reads `W W 1 2 3`. Ignored when
  /// [setType] is `warmup` (those render a `W` badge instead).
  final int displayOrdinal;

  /// Optional label that overrides the numeric [displayOrdinal] in the "Set"
  /// column — used for superset round labels (`A1`, `A2`, `B1`…). Warm-up rows
  /// still render their `W` badge regardless. Null = show the numeric ordinal.
  final String? displayLabel;
  final bool isCompleted;
  final SetType setType;
  final ValueChanged<SetType> onSetTypeSelected;

  /// True when this row is a dropset drop (a linked sub-set). Drops render an
  /// indented `tertiary` bracket + a small "D" badge instead of an ordinal.
  final bool isDrop;

  /// Compact last-session value for the "Previous" column (e.g. `60 kg × 10`,
  /// `5 · 01:30`, `01:30`), or `-` when there is no previous set.
  final String previousSetLabel;

  /// Whether a previous set actually exists — drives the Previous column's
  /// emphasis (a real value reads a touch stronger than the `-` placeholder).
  final bool hasPreviousSet;
  final Widget? weightField;
  final double repsFieldWidth;
  final Widget repsField;
  final Widget completionButton;

  const SetRowContent({
    super.key,
    required this.setIndex,
    required this.displayOrdinal,
    this.displayLabel,
    required this.isCompleted,
    required this.setType,
    required this.onSetTypeSelected,
    this.isDrop = false,
    required this.previousSetLabel,
    required this.hasPreviousSet,
    required this.weightField,
    required this.repsFieldWidth,
    required this.repsField,
    required this.completionButton,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarmup = setType == SetType.warmup;

    // Strong-style: the Set cell IS the set-type selector. Tapping the
    // badge/number opens the type menu — there is no separate icon button.
    //
    // Column order mirrors Strong/Hevy: Set badge | Previous | kg/km | Reps/Time
    // | check. The "Previous" column is the only flexible one (an [Expanded]),
    // so it absorbs the row's slack and ellipsizes on a 320dp phone while the
    // compact, FIXED-width entry fields never shrink. The header row in
    // [ExerciseCard] mirrors this geometry EXACTLY so every label stays centered
    // over its field.
    final content = Row(
      children: [
        SizedBox(
          width: SetRowLayout.setColumnWidth,
          child: SetTypeBadgeMenu(
            setIndex: setIndex,
            setType: setType,
            onSelected: onSetTypeSelected,
            badge: _SetBadge(
              setType: setType,
              isDrop: isDrop,
              isCompleted: isCompleted,
              displayOrdinal: displayOrdinal,
              displayLabel: displayLabel,
            ),
          ),
        ),
        const SizedBox(width: SetRowLayout.previousLeadingGap),
        // "Previous" column — last session's value in a faint secondary style.
        // The fields still ghost the same value as a prefill (Strong shows
        // both), but this explicit column reads at a glance and is natively
        // announced by screen readers. The flexible [Expanded] shrinks/
        // ellipsizes on a 320dp phone so the row never RenderFlex-overflows.
        Expanded(
          child: Text(
            previousSetLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(
                alpha: hasPreviousSet ? 0.8 : 0.5,
              ),
              fontWeight: FontWeight.w500,
              // Tabular figures so previous weight/rep digits line up cleanly.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (weightField != null) ...[
          SizedBox(width: SetRowLayout.weightFieldWidth, child: weightField),
          const SizedBox(width: SetRowLayout.weightTrailingGap),
        ],
        SizedBox(width: repsFieldWidth, child: repsField),
        const SizedBox(width: SetRowLayout.completionLeadingGap),
        completionButton,
      ],
    );

    // De-emphasize the whole warm-up row so working sets read as the main
    // event, while keeping the inputs fully interactive.
    if (isWarmup) {
      return Opacity(opacity: 0.72, child: content);
    }
    // Drops render as an indented, grouped block under their parent: a thin
    // left bracket in `colorScheme.tertiary` plus a small inset so the run of
    // drops reads as one continuous block hanging off the working set.
    if (isDrop) {
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Container(
          key: const Key('dropBracket'),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
                width: 2,
              ),
            ),
          ),
          child: content,
        ),
      );
    }
    return content;
  }
}

/// Small "D" badge shown in the ~30px set-number slot for dropset drops. The
/// drop's `3.1 / 3.2` label sits just beneath it as a quiet caption so the Set
/// column never implies an extra top-level working set.
class _DropBadge extends StatelessWidget {
  const _DropBadge({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tertiary = theme.colorScheme.tertiary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          key: const Key('dropBadge'),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tertiary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            'D',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: tertiary,
            ),
          ),
        ),
        if (label != null && label!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}

/// Small amber "W" badge shown in the ~30px set-number slot for warm-up sets,
/// replacing the ordinal so working sets keep clean `1 / 2 / 3` numbering.
class _WarmupBadge extends StatelessWidget {
  const _WarmupBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.center,
      heightFactor: 1,
      child: Container(
        key: const Key('warmupBadge'),
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accentWarningAmber.withValues(
            alpha: AppColors.setTypeTintAlpha(context),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          'W',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.warmupInk(context),
          ),
        ),
      ),
    );
  }
}

/// The set-number cell rendered INSIDE [SetTypeBadgeMenu]. Picks the badge by
/// type, preserving the existing precedence: warm-up `W`, drop `D` (+ optional
/// `3.1` round label), failure `F`, superset `A1/B2` round label (or an `SS`
/// pill when an ungrouped superset row has no round label), and the plain
/// working ordinal for a regular set.
class _SetBadge extends StatelessWidget {
  const _SetBadge({
    required this.setType,
    required this.isDrop,
    required this.isCompleted,
    required this.displayOrdinal,
    required this.displayLabel,
  });

  final SetType setType;
  final bool isDrop;
  final bool isCompleted;
  final int displayOrdinal;
  final String? displayLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (setType == SetType.warmup) return const _WarmupBadge();
    if (isDrop || setType == SetType.dropset) {
      return _DropBadge(label: displayLabel);
    }
    // Failure shows `F` only for an ungrouped set; a grouped/superset member
    // (non-null [displayLabel], e.g. `A1`) keeps its round label so circuit
    // order stays legible — the `F` would otherwise erase it.
    if (setType == SetType.failure && displayLabel == null) {
      return const _FailureBadge();
    }
    // Superset rows: a grouped member carries its round label (`A1`, `B2`…) in
    // [displayLabel] and renders that as the badge below. But a row re-typed to
    // "Super set" in place — outside any group — has a null [displayLabel];
    // without this branch it would silently fall through to the plain ordinal,
    // making the superset type invisible. Show a clear `SS` indicator instead.
    if (setType == SetType.superset && displayLabel == null) {
      return const _SupersetBadge();
    }
    return Align(
      alignment: Alignment.center,
      // heightFactor: 1 sizes the cell to the glyph instead of letting the
      // [Align] stretch to the row's full height (which would inflate the
      // popup's vertical hit area). Cross-axis centering in the Row handles
      // vertical placement.
      heightFactor: 1,
      child: Text(
        // Superset round labels (`A1`, `B2`…) override the numeric ordinal so
        // round order is self-evident; ungrouped rows keep their plain
        // `1 / 2 / 3` numbering, rendered clean with no colored pill.
        displayLabel ?? '$displayOrdinal',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          // Tabular figures keep the set numbers vertically aligned as the
          // count climbs past 9. The active (uncompleted) row reads a touch
          // crisper than completed rows that have receded.
          fontFeatures: const [FontFeature.tabularFigures()],
          color: isCompleted
              ? theme.colorScheme.onSurface.withValues(alpha: 0.9)
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Small "F" badge shown in the set-number slot for to-failure sets, mirroring
/// the warm-up `W` pill but tinted terracotta (the effort "near-failure"
/// colour, since to-failure IS RIR 0) instead of the destructive/error red.
class _FailureBadge extends StatelessWidget {
  const _FailureBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.center,
      heightFactor: 1,
      child: Container(
        key: const Key('failureBadge'),
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.effortNearFailure.withValues(
            alpha: AppColors.setTypeTintAlpha(context),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          'F',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.failureInk(context),
          ),
        ),
      ),
    );
  }
}

/// Small "SS" badge shown in the set-number slot for a superset set that is NOT
/// part of a grouped run (so it has no `A1`/`B2` round label). Mirrors the
/// warm-up `W` / failure `F` pills, tinted with the theme's secondary token —
/// the same accent the superset link affordance uses — so the type is visible
/// instead of silently reading as a plain ordinal.
class _SupersetBadge extends StatelessWidget {
  const _SupersetBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.secondary;
    return Align(
      alignment: Alignment.center,
      heightFactor: 1,
      child: Container(
        key: const Key('supersetBadge'),
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: secondary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          'SS',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: secondary,
          ),
        ),
      ),
    );
  }
}

/// Strong-style set-type selector: the Set badge/number itself is the trigger.
/// Tapping it opens the type menu (Regular / Warm-up / Failure / Super set /
/// Drop set). Replaces the old separate icon button — there is no extra column.
class SetTypeBadgeMenu extends StatelessWidget {
  final int setIndex;
  final SetType setType;
  final ValueChanged<SetType> onSelected;
  final Widget badge;

  const SetTypeBadgeMenu({
    super.key,
    required this.setIndex,
    required this.setType,
    required this.onSelected,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SetType>(
      // Kept stable for tests/automation: the Set badge is now the trigger.
      key: const Key('setTypeButton'),
      tooltip: 'Set ${setIndex + 1} type',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        _buildTypeMenuItem(context, SetType.regular, 'Regular'),
        _buildTypeMenuItem(context, SetType.warmup, 'Warm-up'),
        _buildTypeMenuItem(context, SetType.failure, 'Failure'),
        _buildTypeMenuItem(context, SetType.superset, 'Super set'),
        _buildTypeMenuItem(context, SetType.dropset, 'Drop set'),
      ],
      // PopupMenuButton ignores `padding` for the `child` form, so give the
      // badge an explicit full-cell hit area (set column width x 44) — otherwise
      // only the ~22px glyph opens the menu.
      // minHeight (not a fixed height, which over-grows a tight drop-set row)
      // gives a comfortable vertical hit area; the badges already left-align to
      // fill the (now 40px) Set column horizontally. No Align/SizedBox wrapper
      // here — that swallows the row's blur tap and regresses focus handling.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: badge,
      ),
    );
  }

  static PopupMenuItem<SetType> _buildTypeMenuItem(
    BuildContext context,
    SetType type,
    String label,
  ) {
    final theme = Theme.of(context);
    return PopupMenuItem(
      value: type,
      child: Row(
        children: [
          _iconForType(type, theme),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  static Widget _iconForType(SetType type, ThemeData theme) {
    return switch (type) {
      SetType.warmup => Icon(
        Icons.wb_sunny,
        color: AppColors.accentWarningAmber,
        size: 20,
      ),
      SetType.failure => Icon(
        Icons.close,
        color: AppColors.effortNearFailure,
        size: 20,
      ),
      SetType.superset => Icon(
        Icons.link,
        color: theme.colorScheme.secondary,
        size: 20,
      ),
      SetType.dropset => Icon(
        Icons.arrow_downward,
        color: theme.colorScheme.tertiary,
        size: 20,
      ),
      _ => Icon(
        Icons.more_horiz,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        size: 20,
      ),
    };
  }
}
