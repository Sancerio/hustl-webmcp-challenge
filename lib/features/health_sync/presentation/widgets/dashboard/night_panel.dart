import 'package:flutter/material.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';

/// The "Night Shift" dark panel hero: intentionally dark ink in BOTH themes
/// (the screen's signature), showing a horizontal stage-composition bar —
/// proportional Deep / Light / REM / Awake segments. This is a COMPOSITION,
/// not a time sequence: only per-stage totals exist, so no hypnogram wave is
/// drawn. A soft dawn-amber fade sits at the right edge — the one gradient in
/// this screen. Sleep start/end times label the bar's ends when known.
class NightPanelHero extends StatelessWidget {
  const NightPanelHero({super.key, required this.snapshot});

  final DailyRecoverySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final segments = stageSegments(snapshot);
    final startLabel = _timeLabel(l10n, snapshot.sleepStart);
    final endLabel = _timeLabel(l10n, snapshot.sleepEnd);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.7, 1.0],
                    colors: [
                      Colors.transparent,
                      AppColors.accentWarningAmber.withValues(alpha: .26),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StageBar(segments: segments),
                if (startLabel != null || endLabel != null) ...[
                  const SizedBox(height: AppSpacing.x1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(startLabel ?? '', style: _ashLabel),
                      Text(endLabel ?? '', style: _ashLabel),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.x2),
                Wrap(
                  spacing: AppSpacing.x2,
                  runSpacing: 6,
                  children: [
                    for (final s in segments) _LegendEntry(segment: s),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _ashLabel = TextStyle(
  color: AppColors.brandAshGray,
  fontSize: 10.5,
  fontWeight: FontWeight.w500,
);

String? _timeLabel(MaterialLocalizations l10n, DateTime? time) {
  if (time == null) return null;
  return l10n.formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()));
}

/// One stage segment of the composition bar.
class StageSegment {
  const StageSegment({
    required this.label,
    required this.minutes,
    required this.color,
  });

  final String label;
  final double minutes;
  final Color color;
}

/// Builds the composition-bar segments from a snapshot's per-stage sleep
/// minutes. Prefers the Deep/Light/REM breakdown when present; falls back to
/// a single "Asleep" segment when only a coarse total is available (e.g. a
/// provider that doesn't report staged sleep) — never inventing a shape the
/// data doesn't have. Awake time (brief awakenings within the night) is its
/// own trailing segment when present.
List<StageSegment> stageSegments(DailyRecoverySnapshot snapshot) {
  final deep = snapshot.deepSleepMinutes ?? 0;
  final light = snapshot.lightSleepMinutes ?? 0;
  final rem = snapshot.remSleepMinutes ?? 0;
  final awake = snapshot.awakeMinutes ?? 0;
  final stagedTotal = deep + light + rem;

  final segments = <StageSegment>[];
  if (stagedTotal > 0) {
    if (deep > 0) {
      segments.add(
        StageSegment(
          label: 'Deep',
          minutes: deep,
          color: AppColors.accentElectricBlue,
        ),
      );
    }
    if (light > 0) {
      segments.add(
        StageSegment(
          label: 'Light',
          minutes: light,
          color: AppColors.accentElectricBlue.withValues(alpha: .42),
        ),
      );
    }
    if (rem > 0) {
      segments.add(
        StageSegment(
          label: 'REM',
          minutes: rem,
          color: AppColors.accentEmeraldGreen,
        ),
      );
    }
  } else if ((snapshot.sleepDurationMinutes ?? 0) > 0) {
    segments.add(
      StageSegment(
        label: 'Asleep',
        minutes: snapshot.sleepDurationMinutes!,
        color: AppColors.accentElectricBlue,
      ),
    );
  }
  if (awake > 0) {
    segments.add(
      StageSegment(
        label: 'Awake',
        minutes: awake,
        color: AppColors.accentWarningAmber,
      ),
    );
  }
  return segments;
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.segments});

  final List<StageSegment> segments;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(height: 18, color: AppColors.outlineDark),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: 18,
        child: Row(
          // Stretch is what makes the segments visible: a childless
          // ColoredBox sizes to constraints.smallest, and a Row's default
          // loose cross-axis constraints would collapse every segment to
          // zero height. The SizedBox bounds the cross axis, so stretch is
          // safe here.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (segments[i].minutes * 10).round().clamp(1, 1 << 20),
                child: ColoredBox(color: segments[i].color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.segment});

  final StageSegment segment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: segment.color,
          ),
        ),
        const SizedBox(width: 6),
        Text(segment.label, style: _ashLabel.copyWith(fontSize: 11)),
      ],
    );
  }
}
