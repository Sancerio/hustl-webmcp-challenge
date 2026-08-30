import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/coaching/coach_insight.dart';
import 'package:hustl_app/core/coaching/explain_section.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/coach_card.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/rec_detail_sheet.dart';

/// Renders the backend's ordered coach recommendations as a stack of the shared
/// [CoachCard]s — the actionable lead of the Insights hub. Each recommendation
/// carries a what-to-do headline, a plain-language why, a trust cue, and an
/// optional action that deep-links into a real nutrition surface (never advisory
/// copy). Empty list renders nothing.
///
/// Item 6 (opt-in): when [coachExplainsOptIn] is true and a [fetchNarrative]
/// callback is provided, the shared [CoachExplainSection] "Explain my numbers"
/// affordance is shown above the cards. Tapping it lazily fetches an LLM note
/// (off the insights load path) and renders it as a lead sentence above the first
/// card. The note is purely additive — on null/error a brief inline "not enough
/// data yet" line is shown (so the loading state never just vanishes) and the
/// cards stand alone. When the range / recs change, the section's [resetKey]
/// changes so a stale note is cleared and the affordance returns.
class InsightsCoachRecommendations extends StatefulWidget {
  const InsightsCoachRecommendations({
    super.key,
    required this.recommendations,
    this.momentumOptIn = false,
    this.coachExplainsOptIn = false,
    this.fetchNarrative,
  });

  final List recommendations;

  /// Whether the opt-in behavioral-momentum tips are enabled (item 4). When
  /// false, any `behavioral_momentum` rec is filtered out client-side too — a
  /// belt-and-suspenders gate so a stale cached response can never surface it.
  final bool momentumOptIn;

  /// Whether the opt-in "Coach explains my numbers" narrative is enabled (item 6).
  final bool coachExplainsOptIn;

  /// Lazy fetcher for the narrative. Non-null only when the user has opted in.
  /// Returns the note string, or null when off/gated/errored.
  final Future<String?> Function()? fetchNarrative;

  @override
  State<InsightsCoachRecommendations> createState() =>
      _InsightsCoachRecommendationsState();
}

class _InsightsCoachRecommendationsState
    extends State<InsightsCoachRecommendations> {
  /// Keys that only render when the user has opted in.
  static const _optInKeys = {'behavioral_momentum'};

  /// The only routes a recommendation may point at — the contract enforces this
  /// server-side; we guard again so a stray route can never crash navigation.
  static const _knownRoutes = {
    '/nutrition',
    '/nutrition/strategy',
    '/nutrition/weight',
    '/add-food',
  };

  /// A content fingerprint of the recommendations the narrative is reasoning
  /// about. Fed to [CoachExplainSection.resetKey] so that when the user switches
  /// the insights range (or recs refetch with different content), the stale note
  /// is cleared and the affordance returns instead of hanging above fresh cards.
  /// The parent rebuilds a fresh list on every refetch, so identity is too eager;
  /// we fingerprint the per-rec `key`/`headline`/`why`.
  static String _recsFingerprint(List recs) {
    final parts = <String>[];
    for (final r in recs) {
      if (r is Map) {
        parts.add('${r['key']}|${r['headline']}|${r['why']}');
      } else {
        parts.add('$r');
      }
    }
    return parts.join('§');
  }

  static CoachTone _tone(String? raw) {
    switch (raw) {
      case 'positive':
        return CoachTone.positive;
      case 'attention':
        return CoachTone.attention;
      default:
        return CoachTone.neutral;
    }
  }

  static CoachConfidence _confidence(String? raw) {
    switch (raw) {
      case 'high':
        return CoachConfidence.high;
      case 'medium':
        return CoachConfidence.medium;
      case 'building':
        return CoachConfidence.building;
      default:
        return CoachConfidence.none;
    }
  }

  CoachInsight _insight(BuildContext context, Map rec) {
    final action = rec['action'];
    CoachAction? coachAction;
    if (action is Map && action['route'] is String) {
      final route = action['route'] as String;
      if (_knownRoutes.contains(route)) {
        coachAction = CoachAction(
          label: (action['label'] as String?) ?? '',
          onTap: () {
            Haptics.selection();
            // Sub-routes and the OS quick action push onto the stack; a tab
            // root resets the stack.
            if (route.startsWith('/nutrition/') || route == '/add-food') {
              context.push(route);
            } else {
              context.go(route);
            }
          },
        );
      }
    }
    return CoachInsight(
      headline: (rec['headline'] as String?) ?? '',
      why: (rec['why'] as String?) ?? '',
      tone: _tone(rec['tone'] as String?),
      confidence: _confidence(rec['confidence'] as String?),
      windowLabel: rec['windowLabel'] as String?,
      action: coachAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final recs = widget.recommendations
        .whereType<Map>()
        .where(
          (r) =>
              widget.momentumOptIn || !_optInKeys.contains(r['key'] as String?),
        )
        .toList();
    if (recs.isEmpty) return const SizedBox.shrink();

    // The narrative affordance only exists when opted in AND a fetcher is wired.
    final fetch = widget.fetchNarrative;
    final canExplain = widget.coachExplainsOptIn && fetch != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canExplain) ...[
          CoachExplainSection(
            fetchNarrative: fetch,
            // Reset the note when the explained numbers change (range / recs).
            resetKey: _recsFingerprint(recs),
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
        for (var i = 0; i < recs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.x2),
          CoachCard(
            insight: _insight(context, recs[i]),
            // The (i) eyebrow opens THIS rec's detail — the user's real numbers
            // and the logic behind the nudge — instead of the generic intro.
            onInfoTap: () {
              Haptics.selection();
              showRecDetail(context, recs[i]);
            },
          ),
        ],
      ],
    );
  }
}
