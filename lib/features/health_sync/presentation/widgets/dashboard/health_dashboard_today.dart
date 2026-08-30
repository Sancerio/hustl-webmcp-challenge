import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/widgets/app_section.dart';
import '../../../../../core/coaching/coach_explain_api.dart';
import '../../../../../core/coaching/explain_section.dart';
import '../../../../../core/coaching/recovery_explain_facts.dart';
import '../../../../../core/services/preferences_service.dart';
import '../../../../../core/widgets/coach_card.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';
import '../../../domain/models/recovery_signal_availability.dart';
import '../../../domain/usecases/recovery_band_copy.dart';
import 'conditions_copy.dart';
import 'conditions_hero.dart';
import 'conditions_instruments.dart';
import 'conditions_week_strip.dart';
import 'day_ledger_section.dart';
import 'recovery_coach.dart';

/// "Conditions Report" (Biology redesign): the "Today" block leads with the
/// conditions hero (recovery as mountain weather), the instruments row
/// (Sleep / HRV / Resting HR vs. baseline), the coach's route call, and a
/// 7-day conditions strip. Replaces the previous ring-hero + strain/sleep
/// metric-row composition; the coaching panel below is unchanged in
/// substance — it already carries the same [recoveryCoachInsight] /
/// [CoachCard] pairing that now doubles as the "route call" card.
class TodayOverviewGroup extends StatelessWidget {
  const TodayOverviewGroup({
    super.key,
    required this.snapshot,
    required this.lastSyncedAt,
    this.recoverySnapshots = const [],
    this.signalAvailability = RecoverySignalAvailability.empty,
    this.isStale = false,
  });

  final DailyRecoverySnapshot? snapshot;
  final DateTime? lastSyncedAt;

  /// The trailing recovery snapshots (typically a 14-day window) used to
  /// derive the instruments' baselines, the hero's lede, and the week strip.
  final List<DailyRecoverySnapshot> recoverySnapshots;
  final RecoverySignalAvailability signalAvailability;

  /// True when [snapshot] is not today's — i.e. today hasn't synced recovery
  /// data yet, so the hero shows the most recent complete day instead. Drives a
  /// subtle "as of <day>" indicator so the surface stays honest.
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = snapshot?.date ?? DateTime.now();
    final l10n = MaterialLocalizations.of(context);
    final snap = snapshot;
    final baselines = snap == null
        ? const ConditionsBaselines()
        : ConditionsBaselines.fromSnapshots(recoverySnapshots, snap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x1,
            AppSpacing.x2,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today', style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                // When today's recovery hasn't synced yet we surface the most
                // recent complete day, so qualify the date with "as of" instead
                // of implying the reading is from today.
                isStale
                    ? 'As of ${l10n.formatFullDate(date.toLocal())}'
                    : l10n.formatFullDate(date.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isStale ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
            0,
          ),
          child: ConditionsHero(
            snapshot: snap,
            sleepBaselineMinutes: baselines.sleepMinutes,
            hrvBaseline: baselines.hrvValue,
            rhrBaseline: baselines.restingHeartRateBpm,
          ),
        ),
        const SectionHeader('Instruments'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: ConditionsInstruments(
            snapshot: snap,
            baselines: baselines,
            signalAvailability: signalAvailability,
          ),
        ),
        // "The day's ledger": the strain receipt that itemizes what drove
        // today's strain. Self-gating and absent-safe — it renders zero height
        // (header included) whenever there is nothing to itemize.
        DayLedgerSection(snapshot: snap),
        _CoachingPanel(snapshot: snap, lastSyncedAt: lastSyncedAt),
        const SectionHeader('Past week'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: ConditionsWeekStrip(snapshots: recoverySnapshots),
        ),
      ],
    );
  }
}

class _CoachingPanel extends StatefulWidget {
  const _CoachingPanel({required this.snapshot, required this.lastSyncedAt});

  final DailyRecoverySnapshot? snapshot;
  final DateTime? lastSyncedAt;

  @override
  State<_CoachingPanel> createState() => _CoachingPanelState();
}

class _CoachingPanelState extends State<_CoachingPanel> {
  // Opt-in "Coach explains my numbers" narrative on the recovery surface. Read
  // once on mount; the note is fetched LAZILY (only when the user taps the
  // affordance) and only when this is true + the reading is settled
  // (!isCalibrating) and trustworthy (confidence != low), so it stays entirely
  // off the load path and never narrates a still-calibrating or rough estimate.
  bool _coachExplainsOptIn = false;
  final _explainApi = CoachExplainApi();

  @override
  void initState() {
    super.initState();
    _loadOptIn();
  }

  Future<void> _loadOptIn() async {
    if (!GetIt.instance.isRegistered<PreferencesService>()) return;
    final optIn = await GetIt.instance<PreferencesService>()
        .getCoachExplainsEnabled();
    if (mounted && optIn != _coachExplainsOptIn) {
      setState(() => _coachExplainsOptIn = optIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = MaterialLocalizations.of(context);
    final snapshot = widget.snapshot;
    final lastSyncedAt = widget.lastSyncedAt;

    final colors = theme.colorScheme;

    // Mirror the backend recovery gate: only offer the explain affordance for a
    // SETTLED (!isCalibrating), TRUSTWORTHY (confidence != low) reading. The
    // backend re-checks this gate, so this just keeps the affordance off the
    // surface when it would return nothing.
    final canExplain =
        snapshot != null &&
        !snapshot.isCalibrating &&
        snapshot.confidence != RecoveryConfidence.low &&
        snapshot.flowBand != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Coaching'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoachCard(insight: recoveryCoachInsight(snapshot)),
              // Opt-in coach note: a quiet "Explain my numbers" affordance under
              // the coach card. Gated on a settled, trustworthy reading + the
              // opt-in. The note is purely additive — the card above and the
              // scores stay authoritative.
              if (_coachExplainsOptIn && canExplain) ...[
                const SizedBox(height: AppSpacing.x1),
                Builder(
                  builder: (context) {
                    // Build the explain facts ONCE so the fetch and the reset key
                    // stay in lockstep: the reset key is derived from the FULL
                    // facts map (every input the narrative depends on — scores,
                    // band, confidence, sleep/load, anomaly + the derived copy),
                    // so any sync that changes ANY of them re-fetches and a stale
                    // note can never hang above fresh data. (Earlier the key used
                    // only readiness/band/strain, missing confidence, sleep, load,
                    // anomaly + guidance — a sync could leave it stale.)
                    final facts = recoveryExplainFacts(snapshot);
                    return CoachExplainSection(
                      fetchNarrative: () =>
                          _explainApi.explain('recovery', facts),
                      resetKey: recoveryExplainResetKey(facts),
                    );
                  },
                ),
              ],
              if (snapshot?.readinessScore != null) ...[
                const SizedBox(height: AppSpacing.x1),
                Text(
                  RecoveryBandCopy.disclaimer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              if (lastSyncedAt != null) ...[
                const SizedBox(height: AppSpacing.x1),
                Text(
                  'Synced ${l10n.formatMediumDate(lastSyncedAt.toLocal())} at ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(lastSyncedAt.toLocal()))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
