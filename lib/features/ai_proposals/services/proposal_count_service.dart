import '../domain/repositories/proposals_repository.dart';
import 'proposal_events_service.dart';

class ProposalCountService {
  ProposalCountService(
    Object? ignored,
    this._repository,
    this._events, {
    Object? notifications,
    Object? preferences,
  });

  final ProposalsRepository _repository;
  final ProposalEventsService _events;

  Future<void> refreshNow() async {
    _events.setCount((await _repository.listPending(limit: 50)).length);
  }

  void start() => refreshNow();
  void stop() {}
}
