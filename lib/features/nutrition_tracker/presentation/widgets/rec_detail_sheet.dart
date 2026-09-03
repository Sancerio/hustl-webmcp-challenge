import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/core/services/haptics.dart';

/// Opens the rec-specific detail sheet for an Insights coach card — replacing
/// the generic "Meet your Coach" explainer for these cards. Renders entirely
/// from data already on the [rec] map (no backend call), so the sheet shows
/// THIS user's real numbers and the plain-language logic behind the nudge.
Future<void> showRecDetail(BuildContext context, Map rec) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) => RecDetailSheet(rec: rec),
  );
}

/// The standalone, testable content of [showRecDetail]. Reads a single backend
/// recommendation map (`key`, `headline`, `why`, `tone`, `confidence`,
/// `windowLabel`, `action`) and explains it: a tone-accented headline echoing
/// the card, the real data snapshot (the rec's `why`), the plain-language LOGIC
/// behind it (keyed off `key`, with a graceful generic fallback), a confidence
/// explainer tied to the tier + window, and the action deep-link. Null-safe for
/// every field. Progressive disclosure keeps it tight: the threshold detail
/// lives behind a "How we calculate this" expander.
class RecDetailSheet extends StatefulWidget {
  const RecDetailSheet({super.key, required this.rec});

  final Map rec;

  @override
  State<RecDetailSheet> createState() => _RecDetailSheetState();
}

class _RecDetailSheetState extends State<RecDetailSheet> {
  bool _logicExpanded = false;

  String? _string(String key) {
    final value = widget.rec[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  CoachTone get _tone {
    switch (_string('tone')) {
      case 'positive':
        return CoachTone.positive;
      case 'attention':
        return CoachTone.attention;
      default:
        return CoachTone.neutral;
    }
  }

  Color _accent() {
    switch (_tone) {
      case CoachTone.positive:
        return AppColors.accentEmeraldGreen;
      case CoachTone.attention:
        return AppColors.accentWarningAmber;
      case CoachTone.neutral:
        return AppColors.accentElectricBlue;
    }
  }

  /// The plain-language threshold/logic behind the nudge, keyed off the rec key.
  /// Future keys fall through to a generic explanation so the sheet never breaks.
  String _logic() {
    switch (_string('key')) {
      case 'energy_trend':
        return 'We compare your average daily intake against your energy '
            'budget — your estimated TDEE once we have one, otherwise your '
            'calorie target. Within about 75 kcal reads as maintenance; '
            'further out we flag a deficit or surplus, and a gap over '
            '500 kcal counts as a large one.';
      case 'protein_low':
        return 'We compare your average logged protein against your adaptive '
            'protein target — bodyweight-scaled and adjusted from your '
            'check-ins, not a flat 100 g. This fires when you average more '
            'than 10% under that target across your logged days.';
      case 'weight_pace':
        return 'We turn your intake-vs-TDEE gap into a weekly weight pace at '
            'about 7,700 kcal per kg, then cross-check it against your logged '
            'weight trend. We only show this once both signals agree.';
      case 'missed_logging':
        return 'We compare how many days you completed a workout in the last 7 '
            'days against how many days you logged food. When you train more '
            'days than you log, we surface this so your energy and recovery '
            'picture stays accurate. Training data comes from your synced or '
            'logged workouts; logging comes from your food diary.';
      default:
        return 'This is drawn from the numbers you log, compared against your '
            'targets over a recent window. We only surface it once the trend '
            'is steady enough to act on.';
    }
  }

  String? _confidenceLine() {
    final window = _string('windowLabel');
    switch (_string('confidence')) {
      case 'high':
        return window == null
            ? 'High confidence — we have seen enough to trust this.'
            : 'High confidence · $window — we have seen enough to trust this.';
      case 'medium':
        return window == null
            ? 'Medium confidence — the trend is forming, not yet locked in.'
            : 'Medium confidence · $window — the trend is forming, not yet '
                  'locked in.';
      case 'building':
        return window == null
            ? 'Still learning — check back in a few days as more data lands.'
            : 'Building confidence · $window — still learning, so check back '
                  'in a few days.';
      default:
        return null;
    }
  }

  void _onAction(String route) {
    Haptics.selection();
    final router = GoRouter.of(context);
    if (context.canPop()) context.pop();
    // Sub-routes and the OS quick action push onto the stack; a tab root resets
    // the stack. Mirrors the deep-link rules on the card itself.
    if (route.startsWith('/nutrition/') || route == '/add-food') {
      router.push(route);
    } else {
      router.go(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _accent();

    final headline = _string('headline') ?? 'Coach insight';
    final why = _string('why');
    final confidenceLine = _confidenceLine();

    final action = widget.rec['action'];
    String? actionLabel;
    String? actionRoute;
    if (action is Map &&
        action['route'] is String &&
        (action['route'] as String).isNotEmpty) {
      actionRoute = action['route'] as String;
      actionLabel = (action['label'] as String?)?.trim();
      if (actionLabel == null || actionLabel.isEmpty) actionLabel = 'Open';
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            AppSpacing.x2,
            AppSpacing.x3,
            AppSpacing.x3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    'Coach',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(headline, style: theme.textTheme.headlineSmall),
              if (why != null) ...[
                const SizedBox(height: AppSpacing.x2),
                _DataSnapshot(accent: accent, why: why),
              ],
              const SizedBox(height: AppSpacing.x2),
              _LogicDisclosure(
                expanded: _logicExpanded,
                logic: _logic(),
                onToggle: () {
                  Haptics.selection();
                  setState(() => _logicExpanded = !_logicExpanded);
                },
              ),
              if (confidenceLine != null) ...[
                const SizedBox(height: AppSpacing.x2),
                _ConfidenceLine(accent: accent, text: confidenceLine),
              ],
              const SizedBox(height: AppSpacing.x2),
              Text(
                'Guidance from what you log — not medical advice.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              if (actionLabel != null && actionRoute != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _onAction(actionRoute!),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: AppColors.onGradient,
                    ),
                    child: Text(actionLabel),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.canPop() ? context.pop() : null,
                    child: const Text('Got it'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The real-numbers snapshot — the rec's `why`, lifted into a tone-tinted card
/// so the user's own data reads as the evidence behind the nudge.
class _DataSnapshot extends StatelessWidget {
  const _DataSnapshot({required this.accent, required this.why});

  final Color accent;
  final String why;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your numbers',
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(why, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}

/// Progressive disclosure for the threshold math — collapsed by default so the
/// sheet stays tight, expandable for the "why this fires" detail.
class _LogicDisclosure extends StatelessWidget {
  const _LogicDisclosure({
    required this.expanded,
    required this.logic,
    required this.onToggle,
  });

  final bool expanded;
  final String logic;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppSpacing.x1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.calculate_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: Text(
                    'How we calculate this',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: AppMotion.fast,
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.emphasizedCurve,
          alignment: Alignment.topLeft,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    logic,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The confidence explainer — a tone-colored dot plus the tier-tied sentence.
class _ConfidenceLine extends StatelessWidget {
  const _ConfidenceLine({required this.accent, required this.text});

  final Color accent;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
