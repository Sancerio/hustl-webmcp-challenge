import 'dart:async';

enum WorkoutChangeKind { created, updated, completed, deleted, cancelled }

class WorkoutChange {
  final WorkoutChangeKind kind;
  final String? sessionId;
  const WorkoutChange({required this.kind, this.sessionId});
}

/// Lightweight in-app event bus for workout state changes.
///
/// Used to refresh screens when the workout state is mutated externally
/// (e.g., from the Apple Watch companion bridge).
class WorkoutEventsService {
  final StreamController<WorkoutChange> _controller =
      StreamController<WorkoutChange>.broadcast();

  Stream<WorkoutChange> get stream => _controller.stream;

  void emit(WorkoutChange change) {
    if (_controller.isClosed) return;
    _controller.add(change);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
