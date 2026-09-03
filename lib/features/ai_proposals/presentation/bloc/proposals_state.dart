import 'package:equatable/equatable.dart';

import '../../domain/models/proposal_summary.dart';

abstract class ProposalsState extends Equatable {
  const ProposalsState();

  @override
  List<Object?> get props => [];
}

class ProposalsInitial extends ProposalsState {
  const ProposalsInitial();
}

class ProposalsLoading extends ProposalsState {
  const ProposalsLoading();
}

/// Loaded inbox.
///
/// [inFlightIds] are proposals with an approve/reject in progress (used to show
/// per-row spinners and disable buttons). [staleIds] are pending siblings that
/// a just-approved proposal made stale (their `base_template_updated_at` no
/// longer matches) — surfaced with a "needs re-propose" affordance instead of
/// an enabled Approve.
class ProposalsLoaded extends ProposalsState {
  const ProposalsLoaded({
    required this.items,
    this.inFlightIds = const {},
    this.staleIds = const {},
    this.appliedTemplateId,
  });

  final List<ProposalSummary> items;
  final Set<String> inFlightIds;
  final Set<String> staleIds;

  /// One-shot: the template id a just-applied (approved) proposal wrote to, so
  /// the approval screen can offer a "View template" jump. Null on plain loads,
  /// rejects, and applies whose template id is unknown.
  final String? appliedTemplateId;

  ProposalsLoaded copyWith({
    List<ProposalSummary>? items,
    Set<String>? inFlightIds,
    Set<String>? staleIds,
    String? appliedTemplateId,
  }) {
    return ProposalsLoaded(
      items: items ?? this.items,
      inFlightIds: inFlightIds ?? this.inFlightIds,
      staleIds: staleIds ?? this.staleIds,
      appliedTemplateId: appliedTemplateId ?? this.appliedTemplateId,
    );
  }

  @override
  List<Object?> get props => [items, inFlightIds, staleIds, appliedTemplateId];
}

class ProposalsFailure extends ProposalsState {
  const ProposalsFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}
