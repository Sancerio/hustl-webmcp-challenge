import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../nutrition_tracker/presentation/diary_refresh_signal.dart';
import '../../../workout_logging/data/services/workout_sync_service.dart';
import '../../data/datasources/proposals_api.dart';
import '../../domain/models/proposal_summary.dart';
import '../../domain/repositories/proposals_repository.dart';

abstract class ProposalHistoryState extends Equatable {
  const ProposalHistoryState();

  @override
  List<Object?> get props => [];
}

class ProposalHistoryInitial extends ProposalHistoryState {
  const ProposalHistoryInitial();
}

class ProposalHistoryLoading extends ProposalHistoryState {
  const ProposalHistoryLoading();
}

/// Loaded history. [inFlightIds] are rows with an in-progress Undo (used to
/// show a per-row spinner and disable the action).
class ProposalHistoryLoaded extends ProposalHistoryState {
  const ProposalHistoryLoaded({
    required this.items,
    this.inFlightIds = const {},
  });

  final List<ProposalSummary> items;
  final Set<String> inFlightIds;

  ProposalHistoryLoaded copyWith({
    List<ProposalSummary>? items,
    Set<String>? inFlightIds,
  }) {
    return ProposalHistoryLoaded(
      items: items ?? this.items,
      inFlightIds: inFlightIds ?? this.inFlightIds,
    );
  }

  @override
  List<Object?> get props => [items, inFlightIds];
}

class ProposalHistoryFailure extends ProposalHistoryState {
  const ProposalHistoryFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}

/// Drives the History tab of the proposals inbox (decided proposals: applied,
/// reverted, rejected). Kept as a standalone [Cubit] rather than folded into
/// [ProposalsBloc] so the pending badge/count and RouteAware-refresh logic on
/// the pending inbox stay uncontaminated by history concerns.
class ProposalHistoryCubit extends Cubit<ProposalHistoryState> {
  ProposalHistoryCubit({
    required ProposalsRepository repository,
    DiaryRefreshSignal? diaryRefreshSignal,
    WorkoutSyncService? workoutSyncService,
  }) : _repository = repository,
       _diaryRefreshSignal = diaryRefreshSignal,
       _workoutSyncService = workoutSyncService,
       super(const ProposalHistoryInitial());

  final ProposalsRepository _repository;
  final DiaryRefreshSignal? _diaryRefreshSignal;
  final WorkoutSyncService? _workoutSyncService;

  /// Bumped on every local mutation (revert). A `_fetch` captures it on entry
  /// and discards its result if a mutation landed meanwhile, so a slow
  /// pull-to-refresh can't clobber a just-undone row back to "Applied".
  int _mutationGen = 0;

  /// Bumped for every fetch so an older request that completes after a newer
  /// one cannot overwrite the newer response.
  int _fetchGen = 0;

  /// Initial load: shows the skeleton while fetching.
  Future<void> load() async {
    emit(const ProposalHistoryLoading());
    await _fetch();
  }

  /// Pull-to-refresh: keeps the current content on screen while re-fetching.
  Future<void> refresh() async {
    await _fetch();
  }

  Future<void> _fetch() async {
    final mutationGen = _mutationGen;
    final fetchGen = ++_fetchGen;
    try {
      final items = await _repository.listDecided();
      // A revert or newer fetch landed while this request was in flight —
      // discard the stale result rather than clobbering newer state.
      if (isClosed || mutationGen != _mutationGen || fetchGen != _fetchGen) {
        return;
      }
      emit(ProposalHistoryLoaded(items: items));
    } on ProposalsApiException catch (e) {
      if (isClosed || mutationGen != _mutationGen || fetchGen != _fetchGen) {
        return;
      }
      emit(ProposalHistoryFailure(code: e.code, message: e.message));
    } catch (e) {
      if (isClosed || mutationGen != _mutationGen || fetchGen != _fetchGen) {
        return;
      }
      emit(ProposalHistoryFailure(code: 'unknown', message: e.toString()));
    }
  }

  /// Undo an applied log proposal. On success, replaces the row in place with
  /// a `reverted` copy (so its Undo action disappears) and pings the affected
  /// surface exactly as `ProposalsBloc._onRevert` does — [DiaryRefreshSignal]
  /// for food kinds, [WorkoutSyncService] for workout logs. Returns whether the
  /// revert succeeded so the caller can show the matching [HustlSnack].
  Future<bool> revert(ProposalSummary p) async {
    // Invalidate any in-flight `_fetch` so its (pre-revert) result can't land
    // after us and re-show this row as still-applied.
    _mutationGen++;
    final loaded = state is ProposalHistoryLoaded
        ? state as ProposalHistoryLoaded
        : null;
    if (loaded != null) {
      emit(loaded.copyWith(inFlightIds: {...loaded.inFlightIds, p.id}));
    }
    try {
      await _repository.revert(p.id);
      if (p.kind == ProposalKind.foodLog ||
          p.kind == ProposalKind.foodLogEdit ||
          p.kind == ProposalKind.foodLogDelete) {
        _diaryRefreshSignal?.ping();
      } else if (p.kind == ProposalKind.workoutLog) {
        await _workoutSyncService?.syncNow();
      }
      final current = state is ProposalHistoryLoaded
          ? state as ProposalHistoryLoaded
          : loaded;
      if (current != null) {
        // Server stamps a fresh decided_at on revert, so advance the local
        // terminal time too — the list re-groups it under "Today".
        final updated = [
          for (final item in current.items)
            if (item.id == p.id)
              item.copyWith(status: 'reverted', decidedAt: DateTime.now())
            else
              item,
        ];
        emit(
          ProposalHistoryLoaded(
            items: updated,
            inFlightIds: current.inFlightIds.where((id) => id != p.id).toSet(),
          ),
        );
      }
      return true;
    } catch (_) {
      final current = state is ProposalHistoryLoaded
          ? state as ProposalHistoryLoaded
          : loaded;
      if (current != null) {
        emit(
          current.copyWith(
            inFlightIds: current.inFlightIds.where((id) => id != p.id).toSet(),
          ),
        );
      }
      return false;
    }
  }
}
