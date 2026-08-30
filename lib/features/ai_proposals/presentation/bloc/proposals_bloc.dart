import 'package:bloc/bloc.dart';

import '../../../../core/services/preferences_service.dart';
import '../../../nutrition_tracker/presentation/diary_refresh_signal.dart';
import '../../../workout_logging/data/services/workout_sync_service.dart';
import '../../../workout_templates/data/services/template_sync_service.dart';
import '../../../workout_templates/domain/repositories/template_repository.dart';
import '../../data/datasources/proposals_api.dart';
import '../../domain/models/proposal_summary.dart';
import '../../domain/repositories/proposals_repository.dart';
import '../../services/proposal_events_service.dart';
import 'proposals_event.dart';
import 'proposals_state.dart';

/// Drives the proposals inbox. Modeled on `AuthBloc` (flutter_bloc + Equatable).
///
/// On approve success it removes the item and pushes the new count via
/// [ProposalEventsService]. For a TEMPLATE approve it also calls
/// [TemplateSyncService.syncNow] to pull the server-executed write, then
/// re-validates pending siblings targeting the same `targetTemplateId`
/// (approving one bumps the target's `updated_at`, making siblings'
/// `base_template_updated_at` stale). For a NUTRITION approve it pings
/// [DiaryRefreshSignal] so the diary/strategy reload the new targets, and skips
/// the template-only sync + sibling re-validation (which are templateId-keyed).
class ProposalsBloc extends Bloc<ProposalsEvent, ProposalsState> {
  ProposalsBloc({
    required ProposalsRepository repository,
    required ProposalEventsService events,
    required TemplateRepository templateRepository,
    TemplateSyncService? syncService,
    DiaryRefreshSignal? diaryRefreshSignal,
    WorkoutSyncService? workoutSyncService,
    PreferencesService? preferences,
  }) : _repository = repository,
       _events = events,
       _templateRepository = templateRepository,
       _syncService = syncService,
       _diaryRefreshSignal = diaryRefreshSignal,
       _workoutSyncService = workoutSyncService,
       _preferences = preferences,
       super(const ProposalsInitial()) {
    on<LoadProposals>(_onLoad);
    on<RefreshProposals>(_onRefresh);
    on<ApproveProposal>(_onApprove);
    on<RejectProposal>(_onReject);
    on<RevertProposal>(_onRevert);
  }

  final ProposalsRepository _repository;
  final ProposalEventsService _events;
  final TemplateRepository _templateRepository;
  final TemplateSyncService? _syncService;
  final DiaryRefreshSignal? _diaryRefreshSignal;
  final WorkoutSyncService? _workoutSyncService;
  final PreferencesService? _preferences;

  Future<void> _onLoad(
    LoadProposals event,
    Emitter<ProposalsState> emit,
  ) async {
    emit(const ProposalsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshProposals event,
    Emitter<ProposalsState> emit,
  ) async {
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<ProposalsState> emit) async {
    try {
      final items = await _repository.listPending(limit: 50);
      _events.setCount(items.length);
      emit(ProposalsLoaded(items: items));
    } on ProposalsApiException catch (e) {
      emit(ProposalsFailure(code: e.code, message: e.message));
    } catch (e) {
      emit(ProposalsFailure(code: 'unknown', message: e.toString()));
    }
  }

  Future<void> _onApprove(
    ApproveProposal event,
    Emitter<ProposalsState> emit,
  ) async {
    // Proceed even when the inbox isn't ProposalsLoaded (deep-linked detail page,
    // or a prior ProposalsFailure the user is retrying) — otherwise the action
    // would silently no-op. Optimistic list updates apply only when loaded.
    final loaded = state is ProposalsLoaded ? state as ProposalsLoaded : null;
    String? approvedTargetId;
    ProposalSummary? approvedItem;
    if (loaded != null) {
      final matches = loaded.items.where((p) => p.id == event.id);
      approvedItem = matches.isEmpty ? null : matches.first;
      approvedTargetId = approvedItem?.targetTemplateId;
      emit(loaded.copyWith(inFlightIds: {...loaded.inFlightIds, event.id}));
    }
    // When the inbox isn't loaded (deep-link) we don't know the kind, so refresh
    // every surface (each is cheap/no-op when irrelevant). When loaded, refresh
    // precisely by kind: templates → template sync; nutrition/food → diary;
    // workout logs → workout-session sync.
    final kind = approvedItem?.kind;
    final refreshTemplate = kind == null ||
        kind == ProposalKind.templateCreate ||
        kind == ProposalKind.templateEdit;
    final refreshDiary = kind == null ||
        kind == ProposalKind.nutritionTargets ||
        kind == ProposalKind.foodLog ||
        kind == ProposalKind.foodLogEdit ||
        kind == ProposalKind.foodLogDelete;
    final refreshWorkout = kind == null || kind == ProposalKind.workoutLog;
    try {
      final approveResult = await _repository.approve(
        event.id,
        idempotencyKey: event.idempotencyKey,
        // The user's LOCAL date so a nutrition proposal resolves to the week the
        // user is actually in (the server only knows UTC). Harmless for templates.
        asOfDate: _localDateIso(DateTime.now()),
      );
      // The approve succeeded — bump the lifetime approved-proposals counter
      // (feeds the coach-readiness loop). Best-effort: a prefs write failure must
      // never turn a successful approve into a user-visible error.
      try {
        await _preferences?.incrementApprovedProposalsCount();
      } catch (_) {}
      // The created template (for an edit, the target it wrote to) — surfaced so
      // the approval screen can offer a "View template" jump.
      final appliedTemplateId = approveResult.templateId ?? approvedTargetId;
      // Pull the server-executed write into the right local store: template sync
      // for template kinds, the diary refresh signal for nutrition + food logs,
      // and a workout-session sync for logged workouts.
      if (refreshTemplate) await _syncService?.syncNow();
      if (refreshDiary) _diaryRefreshSignal?.ping();
      if (refreshWorkout) await _workoutSyncService?.syncNow();
      if (loaded != null) {
        final remaining = loaded.items.where((p) => p.id != event.id).toList();
        _events.setCount(remaining.length);
        final fresh = await _revalidateSiblings(remaining, approvedTargetId);
        // Keep stale flags for OTHER targets — _revalidateSiblings only covers
        // the approved target's siblings, so a wholesale replace would drop
        // valid flags on unrelated rows. Carry the prior flags forward,
        // intersected with the surviving items, and union the fresh set.
        final remainingIds = remaining.map((p) => p.id).toSet();
        final staleIds = {
          ...loaded.staleIds.where(remainingIds.contains),
          ...fresh,
        };
        emit(
          ProposalsLoaded(
            items: remaining,
            inFlightIds: const {},
            staleIds: staleIds,
            appliedTemplateId: appliedTemplateId,
          ),
        );
      } else {
        // Deep-link/notification approve with no loaded inbox. The approve
        // already succeeded, so emit a terminal success the approval screen
        // recognizes as "done" (proposal absent from an empty list) and pops.
        // Do NOT trigger a refresh here: a follow-up fetch failure would emit
        // ProposalsFailure, surfacing a red error over an already-applied
        // proposal and never popping. The inbox refreshes on return via
        // RouteAware.didPopNext, and the badge is reconciled by the poller — we
        // don't touch the count here since the true remaining set is unknown
        // (the inbox was never loaded) and a 0 could hide other pending rows.
        emit(
          ProposalsLoaded(
            items: const [],
            appliedTemplateId: appliedTemplateId,
          ),
        );
      }
    } on ProposalsApiException catch (e) {
      // On a conflict the row may now be stale — re-fetch so the list is honest.
      if (_isConflict(e.code)) add(const RefreshProposals());
      emit(ProposalsFailure(code: e.code, message: e.message));
    } catch (e) {
      emit(ProposalsFailure(code: 'unknown', message: e.toString()));
    }
  }

  Future<void> _onReject(
    RejectProposal event,
    Emitter<ProposalsState> emit,
  ) async {
    final loaded = state is ProposalsLoaded ? state as ProposalsLoaded : null;
    if (loaded != null) {
      emit(loaded.copyWith(inFlightIds: {...loaded.inFlightIds, event.id}));
    }
    try {
      await _repository.reject(event.id, reason: event.reason);
      if (loaded != null) {
        final remaining = loaded.items.where((p) => p.id != event.id).toList();
        _events.setCount(remaining.length);
        emit(
          ProposalsLoaded(
            items: remaining,
            inFlightIds: const {},
            staleIds: loaded.staleIds.where((id) => id != event.id).toSet(),
          ),
        );
      } else {
        add(const RefreshProposals());
      }
    } on ProposalsApiException catch (e) {
      emit(ProposalsFailure(code: e.code, message: e.message));
    } catch (e) {
      emit(ProposalsFailure(code: 'unknown', message: e.toString()));
    }
  }

  /// Undo an APPLIED log proposal (food_log/workout_log). The write is deleted
  /// server-side; here we refresh the affected surface. Applied proposals aren't
  /// in the pending inbox, so the list/count are untouched. A failure surfaces a
  /// toast but never throws.
  Future<void> _onRevert(
    RevertProposal event,
    Emitter<ProposalsState> emit,
  ) async {
    try {
      await _repository.revert(event.id);
      if (event.kind == ProposalKind.foodLog ||
          event.kind == ProposalKind.foodLogEdit ||
          event.kind == ProposalKind.foodLogDelete) {
        _diaryRefreshSignal?.ping();
      } else if (event.kind == ProposalKind.workoutLog) {
        await _workoutSyncService?.syncNow();
      }
    } on ProposalsApiException catch (e) {
      emit(ProposalsFailure(code: e.code, message: e.message));
    } catch (e) {
      emit(ProposalsFailure(code: 'unknown', message: e.toString()));
    }
  }

  /// Re-fetch detail for pending edit-siblings on [targetTemplateId] and mark
  /// any whose snapshot no longer matches the (now-bumped) template as stale.
  /// The server remains the authority; this is a UX pre-empt.
  Future<Set<String>> _revalidateSiblings(
    List<ProposalSummary> items,
    String? targetTemplateId,
  ) async {
    if (targetTemplateId == null || targetTemplateId.isEmpty) return const {};
    final siblings = items.where(
      (p) => p.isEdit && p.targetTemplateId == targetTemplateId,
    );
    if (siblings.isEmpty) return const {};
    DateTime? currentUpdatedAt;
    try {
      final tpl = await _templateRepository.getWorkoutTemplate(
        targetTemplateId,
      );
      currentUpdatedAt = tpl?.updatedAt;
    } catch (_) {
      return const {};
    }
    if (currentUpdatedAt == null) return const {};
    final stale = <String>{};
    for (final sibling in siblings) {
      try {
        final detail = await _repository.getProposal(sibling.id);
        final base = detail.baseTemplateUpdatedAt;
        if (base == null || base.toUtc().isBefore(currentUpdatedAt.toUtc())) {
          stale.add(sibling.id);
        }
      } catch (_) {
        // Leave un-flagged; the server will reject on approve if truly stale.
      }
    }
    return stale;
  }

  bool _isConflict(String code) =>
      code == 'base_version_stale' ||
      code == 'template_cap' ||
      code == 'proposal_expired' ||
      code == 'not_claimable' ||
      // A food-log revision whose target was removed/changed since it was proposed —
      // it's now terminal server-side, so refresh the inbox to drop it.
      code == 'target_missing' ||
      code == 'target_changed' ||
      code == 'not_found';

  /// The LOCAL calendar date as YYYY-MM-DD (DateTime.now() is local). Sent on
  /// approve so the backend resolves a nutrition proposal's week in the user's
  /// timezone rather than UTC.
  static String _localDateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
