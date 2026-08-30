import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/core/widgets/coach_intro_sheet.dart';

/// The single, shared "Coach" card used across nutrition, training and recovery
/// so proactive guidance always reads as ONE coherent coach. Anatomy: a tappable
/// "Coach" eyebrow (opens the "meet your Coach" explainer), a what-to-do
/// HEADLINE, a plain-language WHY, a confidence cue, and an optional action.
/// Adherence-neutral by design — the accent never goes red. The first time a
/// card appears anywhere, the explainer is shown once proactively.
///
/// By default the (i) eyebrow opens the generic "Meet your Coach" explainer.
/// Surfaces that have a richer, rec-specific story to tell (e.g. the Insights
/// coach stack) pass [onInfoTap] to open their own detail sheet instead — the
/// card stays domain-agnostic and never reaches into a feature's data shape.
class CoachCard extends StatefulWidget {
  const CoachCard({super.key, required this.insight, this.onInfoTap});

  final CoachInsight insight;

  /// Optional override for the (i) eyebrow tap. When null the eyebrow opens the
  /// shared [showCoachIntro] explainer; when set it replaces that handler.
  final VoidCallback? onInfoTap;

  @override
  State<CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends State<CoachCard> {
  @override
  void initState() {
    super.initState();
    // Auto-show the generic "Meet your Coach" intro ONLY on cards that fall back
    // to the shared explainer. Cards with a rec-specific [onInfoTap] (e.g. the
    // Insights coach stack) have their own (i) story, so the generic auto-intro
    // would be redundant on that surface — suppress it there.
    if (widget.onInfoTap != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeAutoShowCoachIntro(context);
    });
  }

  Color _accent() {
    switch (widget.insight.tone) {
      case CoachTone.positive:
        return AppColors.accentEmeraldGreen;
      case CoachTone.attention:
        return AppColors.accentWarningAmber;
      case CoachTone.neutral:
        return AppColors.accentElectricBlue;
    }
  }

  String? _confidenceLabel() {
    switch (widget.insight.confidence) {
      case CoachConfidence.high:
        return 'High confidence';
      case CoachConfidence.medium:
        return 'Medium confidence';
      case CoachConfidence.building:
        return 'Building confidence';
      case CoachConfidence.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final insight = widget.insight;
    final accent = _accent();
    final confidenceLabel = _confidenceLabel();
    final action = insight.action;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.onInfoTap ?? () => showCoachIntro(context),
            borderRadius: BorderRadius.circular(AppSpacing.x1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    'Coach',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            insight.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            insight.why,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (insight.note != null) ...[
            const SizedBox(height: AppSpacing.x1),
            Text(
              insight.note!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
          if (confidenceLabel != null) ...[
            const SizedBox(height: AppSpacing.x1 + 2),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    insight.windowLabel == null
                        ? confidenceLabel
                        : '$confidenceLabel · ${insight.windowLabel}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.x1),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: action.onTap,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x1,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        action.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward, size: 16, color: accent),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
