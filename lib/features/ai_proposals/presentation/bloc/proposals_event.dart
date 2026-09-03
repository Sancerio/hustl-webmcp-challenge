import 'package:equatable/equatable.dart';

import '../../domain/models/proposal_summary.dart';

abstract class ProposalsEvent extends Equatable {
  const ProposalsEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the pending inbox.
class LoadProposals extends ProposalsEvent {
  const LoadProposals();
}

/// Pull-to-refresh / silent re-fetch.
class RefreshProposals extends ProposalsEvent {
  const RefreshProposals();
}

/// Approve a proposal. [idempotencyKey] is generated once per attempt by the
/// caller and reused on retry so a double-tap can't double-write.
class ApproveProposal extends ProposalsEvent {
  const ApproveProposal(this.id, {required this.idempotencyKey});

  final String id;
  final String idempotencyKey;

  @override
  List<Object?> get props => [id, idempotencyKey];
}

/// Reject (dismiss) a proposal.
class RejectProposal extends ProposalsEvent {
  const RejectProposal(this.id, {this.reason});

  final String id;
  final String? reason;

  @override
  List<Object?> get props => [id, reason];
}

/// Undo an APPLIED log proposal (food_log/workout_log). [kind] lets the handler
/// refresh the right surface (diary for food, workout history for workouts)
/// without a loaded inbox.
class RevertProposal extends ProposalsEvent {
  const RevertProposal(this.id, {required this.kind});

  final String id;
  final ProposalKind kind;

  @override
  List<Object?> get props => [id, kind];
}
