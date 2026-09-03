import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/services/preferences_service.dart';
import '../../../../../core/widgets/app_section.dart';
import '../../../../workout_logging/domain/models/workout_session.dart';
import '../../../../workout_logging/domain/repositories/workout_repository.dart';
import '../../../data/sources/external_activity_reader.dart';
import '../../../domain/models/daily_recovery_snapshot.dart';
import '../../../domain/models/external_activity.dart';
import '../../../domain/models/strain_ledger.dart';
import '../../../domain/services/external_activity_filter.dart';
import '../../../domain/services/strain_attribution_service.dart';
import 'day_ledger_receipt.dart';

/// Resolves the ledger to render (or null to render nothing) for the current
/// "show workouts from other apps" toggle value.
typedef DayLedgerLoad = Future<StrainLedger?> Function(bool showExternals);

/// "The day's ledger" section: the [SectionHeader] plus the [DayLedgerReceipt],
/// wired to the displayed snapshot's day. It is entirely absent-safe — every
/// absence rule resolves to a null ledger and the section renders zero height,
/// leaving the dashboard pixel-identical for users without health DI, without a
/// strain score, or on ambient-only days. When the WORKOUT read scope is
/// denied, external lines are simply absent (Hustl rows + ambient still
/// itemize) and the read path never prompts.
///
/// Data wiring lives here (presentation glue) and only *consumes* the plan-011
/// services; the attribution math stays in [StrainAttributionService].
class DayLedgerSection extends StatefulWidget {
  const DayLedgerSection({super.key, required this.snapshot, this.loader});

  final DailyRecoverySnapshot? snapshot;

  /// Overridable loader for tests. Defaults to the GetIt-backed composition.
  final DayLedgerLoad? loader;

  @override
  State<DayLedgerSection> createState() => _DayLedgerSectionState();
}

class _DayLedgerSectionState extends State<DayLedgerSection> {
  Future<StrainLedger?>? _future;
  DailyRecoverySnapshot? _computedSnapshot;
  DayLedgerLoad? _computedLoader;
  bool? _computedShowExternals;

  /// The observable Settings toggle, when a [PreferencesService] is registered.
  /// Subscribing (rather than only reading at build) is what actually SCHEDULES
  /// a rebuild when the user flips the toggle and returns from Settings —
  /// nothing else re-builds a still-mounted Health route. Null in DI-less hosts
  /// (tests), where the section behaves as today: default ON, no subscription.
  ValueListenable<bool>? _toggleListenable;

  @override
  void initState() {
    super.initState();
    final gi = GetIt.instance;
    if (gi.isRegistered<PreferencesService>()) {
      _toggleListenable =
          gi<PreferencesService>().showExternalWorkoutsInDayListenable;
      _toggleListenable!.addListener(_onToggleChanged);
    }
  }

  @override
  void dispose() {
    _toggleListenable?.removeListener(_onToggleChanged);
    super.dispose();
  }

  void _onToggleChanged() {
    if (!mounted) return;
    // The rebuild is the point: build() re-runs _ensureFuture, which sees the
    // new toggle value and re-triggers the load.
    setState(() {});
  }

  /// Reads the Settings toggle synchronously (guarded; defaults ON). Kept as a
  /// build-time check alongside the listener subscription (belt and
  /// suspenders): any rebuild from any cause also picks up the current value.
  bool _readShowExternals() {
    final listenable = _toggleListenable;
    if (listenable != null) return listenable.value;
    final gi = GetIt.instance;
    if (!gi.isRegistered<PreferencesService>()) return true;
    return gi<PreferencesService>().showExternalWorkoutsInDay;
  }

  /// Recomputes the cached future when any of its inputs — snapshot, loader, or
  /// the externals toggle — differ from what the current future was computed
  /// with. Called from build so a Settings flip is noticed on rebuild.
  void _ensureFuture() {
    final showExternals = _readShowExternals();
    if (_future != null &&
        identical(_computedLoader, widget.loader) &&
        _computedSnapshot == widget.snapshot &&
        _computedShowExternals == showExternals) {
      return;
    }
    _computedSnapshot = widget.snapshot;
    _computedLoader = widget.loader;
    _computedShowExternals = showExternals;
    final loader = widget.loader;
    _future = loader != null
        ? loader(showExternals)
        : loadDayLedgerFromGetIt(widget.snapshot, showExternals: showExternals);
  }

  @override
  Widget build(BuildContext context) {
    _ensureFuture();
    return FutureBuilder<StrainLedger?>(
      future: _future,
      builder: (context, snapshot) {
        // Only a COMPLETED load renders: FutureBuilder retains the PREVIOUS
        // future's data while a replaced future is pending, so without this
        // gate stale rows (e.g. externals right after a toggle flip) could
        // paint for the waiting frames. A momentary absence during recompute
        // is the correct behavior per the absence rules — this secondary
        // section is absent, never stale and never spinner-only.
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final ledger = snapshot.data;
        if (ledger == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader("The day's ledger"),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
              child: DayLedgerReceipt(
                ledger: ledger,
                typicalStrain: widget.snapshot?.typicalStrainScore,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Builds the snapshot day's ledger from the registered plan-011 services, or
/// null when any absence rule applies. Never throws — any failure resolves to
/// null so the section stays absent-safe. NEVER prompts: the external read is
/// silent (see [ExternalActivityReader.readActivities]) and comes back empty
/// when the WORKOUT scope is absent.
Future<StrainLedger?> loadDayLedgerFromGetIt(
  DailyRecoverySnapshot? snapshot, {
  required bool showExternals,
  GetIt? getIt,
}) async {
  final gi = getIt ?? GetIt.instance;
  if (snapshot == null) return null;

  // DI unregistered → render nothing (pixel-identical dashboard).
  if (!gi.isRegistered<WorkoutRepository>() ||
      !gi.isRegistered<ExternalActivityReader>() ||
      !gi.isRegistered<ExternalActivityFilter>() ||
      !gi.isRegistered<StrainAttributionService>() ||
      !gi.isRegistered<PreferencesService>()) {
    return null;
  }

  try {
    final repo = gi<WorkoutRepository>();
    final reader = gi<ExternalActivityReader>();
    final filter = gi<ExternalActivityFilter>();
    final attribution = gi<StrainAttributionService>();
    final prefs = gi<PreferencesService>();

    final writebackMap = await prefs.getWorkoutWritebackMappings();

    return computeDayLedger(
      snapshot: snapshot,
      readSessions: (start, end) =>
          repo.getWorkoutSessions(startDate: start, endDate: end),
      readExternals: (start, end) =>
          reader.readActivities(start: start, end: end),
      filter: filter,
      attribution: attribution,
      hustlWritebackUuids: writebackMap.values.toSet(),
      showExternals: showExternals,
    );
  } catch (_) {
    return null;
  }
}

/// Pure composition of the snapshot day's strain ledger from injected
/// collaborators.
///
/// The day window is derived from `snapshot.date` (midnight-normalized
/// `[date, date+1)`) — never from the wall clock — so a dashboard showing a
/// FALLBACK day ("as of <earlier day>") attributes that day's sessions, not
/// today's. Sessions are queried with a padded start (the repository filters on
/// start time, which would drop a session crossing midnight INTO the ledger's
/// day) and then overlap-filtered against the window here.
///
/// Returns null when there is nothing to itemize: no snapshot, no strain score,
/// or a ledger with no session entries (an ambient-only day never renders the
/// receipt). A denied WORKOUT read scope is NOT an absence rule: [readExternals]
/// simply yields nothing and the receipt itemizes Hustl rows + ambient. When
/// [showExternals] is false the externals are dropped *before* attribution, so
/// their share is re-absorbed into ambient movement by the service rather than
/// manually renormalized.
Future<StrainLedger?> computeDayLedger({
  required DailyRecoverySnapshot? snapshot,
  required Future<List<WorkoutSession>> Function(DateTime start, DateTime end)
  readSessions,
  required Future<List<ExternalActivity>> Function(DateTime start, DateTime end)
  readExternals,
  required ExternalActivityFilter filter,
  required StrainAttributionService attribution,
  required Set<String> hustlWritebackUuids,
  required bool showExternals,
}) async {
  final snap = snapshot;
  if (snap == null) return null;

  final score = snap.strainScore;
  if (score == null || score <= 0) return null;

  // The ledger explains THIS snapshot's day (which may be a fallback day, not
  // today).
  final date = snap.date.toLocal();
  final dayStart = DateTime(date.year, date.month, date.day);
  // Calendar next-midnight (not dayStart + 24h) so the window stays a true
  // civil day across a DST transition.
  final dayEnd = DateTime(date.year, date.month, date.day + 1);

  // Pad the session query by the same maximum-workout lookback the external
  // reader uses: the repository filters on START time, so an exact-window query
  // would drop a session that starts before midnight and ends inside the day.
  final sessions = await readSessions(
    dayStart.subtract(ExternalActivityReader.maxWorkoutLookback),
    dayEnd,
  );
  final hustl = sessions
      .where(
        (s) =>
            s.isCompleted &&
            s.endTime != null &&
            s.endTime!.isAfter(dayStart) &&
            s.startTime.isBefore(dayEnd),
      )
      .toList();

  var externals = const <ExternalActivity>[];
  if (showExternals) {
    final raw = await readExternals(dayStart, dayEnd);
    externals = filter.filter(
      activities: raw,
      hustlWritebackUuids: hustlWritebackUuids,
      hustlSessions: hustl,
    );
  }

  final ledger = attribution.attribute(
    day: snap,
    hustlSessions: hustl,
    externals: externals,
  );
  return ledger.hasSessionEntries ? ledger : null;
}
