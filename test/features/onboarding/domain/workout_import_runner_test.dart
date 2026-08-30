import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/onboarding/domain/workout_import_runner.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';

/// In-memory [WorkoutRepository] that exercises only the three methods the
/// runner touches; any other call throws via the default [noSuchMethod].
class _FakeWorkoutRepository implements WorkoutRepository {
  _FakeWorkoutRepository([List<WorkoutSession>? seed]) : store = [...?seed];

  final List<WorkoutSession> store;

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => List.of(store);

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async {
    store.add(session);
    return session;
  }

  @override
  Future<void> deleteWorkoutSession(String id) async {
    store.removeWhere((s) => s.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WorkoutSession _session(String id, String name, DateTime start) {
  return WorkoutSession(
    id: id,
    name: name,
    startTime: start,
    exercises: const [],
  );
}

void main() {
  group('WorkoutImportRunner.run', () {
    test('imports new sessions and reports progress to completion', () async {
      final repo = _FakeWorkoutRepository();
      final runner = WorkoutImportRunner(repository: repo);

      final progress = <List<int>>[];
      final outcome = await runner.run([
        _session('a', 'Push', DateTime(2023, 1, 1)),
        _session('b', 'Pull', DateTime(2023, 1, 2)),
      ], onProgress: (done, total) => progress.add([done, total]));

      expect(outcome.imported, 2);
      expect(outcome.replaced, 0);
      expect(repo.store.length, 2);
      expect(progress.last, [2, 2]);
    });

    test('replaces a colliding session (same name + start time)', () async {
      final t1 = DateTime(2023, 1, 1);
      final repo = _FakeWorkoutRepository([
        _session('old-a', 'Push', t1), // collides with the import below
        _session('old-b', 'Pull', DateTime(2023, 1, 2)), // untouched
      ]);
      final runner = WorkoutImportRunner(repository: repo);

      final outcome = await runner.run([
        _session('new-a', 'Push', t1), // same key as old-a -> replace
        _session('new-c', 'Legs', DateTime(2023, 1, 3)), // brand new
      ]);

      expect(outcome.imported, 2);
      expect(outcome.replaced, greaterThan(0));
      expect(outcome.replaced, 1);

      final ids = repo.store.map((s) => s.id).toList();
      expect(ids, contains('new-a'));
      expect(ids, contains('new-c'));
      expect(ids, contains('old-b'));
      expect(ids, isNot(contains('old-a'))); // replaced in place
      expect(repo.store.length, 3);
    });

    test('empty import is a no-op', () async {
      final repo = _FakeWorkoutRepository();
      final outcome = await WorkoutImportRunner(repository: repo).run(const []);

      expect(outcome.imported, 0);
      expect(outcome.replaced, 0);
      expect(outcome.isEmpty, isTrue);
      expect(repo.store, isEmpty);
    });
  });
}
