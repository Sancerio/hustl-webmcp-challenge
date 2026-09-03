import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/active_workout_web_mcp_controller.dart';
import 'package:hustl_app/core/webmcp/web_mcp_access_gate.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';

void main() {
  late ActiveWorkoutWebMcpController controller;
  late WorkoutSession current;
  late List<StagedWorkoutAdjustment> applied;
  late int ownerToken;

  setUp(() {
    controller = ActiveWorkoutWebMcpController();
    current = _session();
    applied = [];
    ownerToken = controller.attach(
      readSession: () => current,
      apply: (adjustment) async {
        applied.add(adjustment);
        return true;
      },
    );
  });

  tearDown(() => controller.dispose());

  test('reads a bounded active workout with opaque target ids', () {
    final result = controller.getActiveWorkout();

    expect(result['status'], 'ready');
    expect(result['sessionId'], 'session-1');
    final exercises = result['exercises']! as List<Object?>;
    final exercise = exercises.single! as Map<String, Object?>;
    expect(exercise['exerciseId'], 'exercise-1');
    final sets = exercise['sets']! as List<Object?>;
    expect(sets.first, containsPair('setId', 'set-1'));
  });

  test('stages a visible diff without mutating the session', () {
    final result = controller.stage(const {
      'changes': [
        {
          'exerciseId': 'exercise-1',
          'setId': 'set-1',
          'weight': 62.5,
          'reps': 10,
          'rpe': 8,
        },
      ],
    });

    expect(result['status'], 'staged');
    expect(result['requiresHumanReview'], isTrue);
    expect(current.exercises.single.sets.first.weight, 60);
    final pending = controller.pendingFor(current)!;
    expect(pending.changes.single.before.weight, 60);
    expect(pending.changes.single.after.weight, 62.5);
  });

  test('rejects completed, duplicate, no-op, and out-of-range changes', () {
    expect(
      controller.stage(const {
        'changes': [
          {'exerciseId': 'exercise-1', 'setId': 'set-2', 'reps': 12},
        ],
      })['code'],
      'completed_set_immutable',
    );
    expect(
      controller.stage(const {
        'changes': [
          {'exerciseId': 'exercise-1', 'setId': 'set-1', 'weight': 60},
        ],
      })['code'],
      'no_change',
    );
    expect(
      controller.stage(const {
        'changes': [
          {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 1001},
        ],
      })['code'],
      'value_out_of_range',
    );
    expect(
      controller.stage(const {
        'changes': [
          {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 9},
          {'exerciseId': 'exercise-1', 'setId': 'set-1', 'rpe': 8},
        ],
      })['code'],
      'duplicate_target',
    );
  });

  test('manual revision invalidates the stage before Apply', () async {
    controller.stage(const {
      'changes': [
        {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 9},
      ],
    });
    final exercise = current.exercises.single;
    current = current.copyWith(
      exercises: [
        exercise.copyWith(
          sets: [exercise.sets.first.copyWith(weight: 61), exercise.sets.last],
        ),
      ],
    );

    expect(await controller.applyPending(), isFalse);
    expect(controller.pending.value, isNull);
    expect(applied, isEmpty);
  });

  test('unrelated session metadata does not invalidate the stage', () async {
    controller.stage(const {
      'changes': [
        {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 9},
      ],
    });
    final revision = controller.pending.value!.baseRevision;
    current = current.copyWith(
      lastUpdatedAt: DateTime(2026, 8, 27, 9, 5),
      dirty: false,
      watchRecordingActive: true,
    );

    expect(controller.pendingFor(current)?.baseRevision, revision);
    expect(await controller.applyPending(), isTrue);
  });

  test('cannot stage a set outside the bounded read window', () {
    final exercise = current.exercises.single;
    current = current.copyWith(
      exercises: [
        exercise.copyWith(
          sets: List.generate(
            21,
            (index) =>
                WorkoutSet(id: 'bounded-set-${index + 1}', weight: 60, reps: 8),
          ),
        ),
      ],
    );

    expect(
      controller.stage(const {
        'changes': [
          {'exerciseId': 'exercise-1', 'setId': 'bounded-set-21', 'reps': 9},
        ],
      })['code'],
      'set_not_found',
    );
  });

  test('auth transition invalidates the owner and pending review', () async {
    controller.dispose();
    final gate = WebMcpAccessGate()..setReady(true);
    controller = ActiveWorkoutWebMcpController(accessGate: gate);
    controller.attach(
      readSession: () => current,
      apply: (adjustment) async {
        applied.add(adjustment);
        return true;
      },
    );
    controller.stage(const {
      'changes': [
        {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 9},
      ],
    });

    final generation = gate.closeForTransition();
    gate.openIfCurrent(generation);

    expect(controller.pending.value, isNull);
    expect(controller.getActiveWorkout()['code'], 'no_active_workout');
    expect(await controller.applyPending(), isFalse);
    expect(applied, isEmpty);

    controller.attach(readSession: () => current, apply: (_) async => true);
    expect(controller.getActiveWorkout()['status'], 'ready');
  });

  test('Apply and Discard are explicit human actions', () async {
    controller.stage(const {
      'changes': [
        {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 9},
      ],
    });
    expect(await controller.applyPending(), isTrue);
    expect(applied, hasLength(1));
    expect(controller.pending.value, isNull);

    controller.stage(const {
      'changes': [
        {'exerciseId': 'exercise-1', 'setId': 'set-1', 'rpe': 8},
      ],
    });
    controller.discard();
    expect(controller.pending.value, isNull);
  });

  test('detaching the screen owner clears and disables the stage', () {
    controller.stage(const {
      'changes': [
        {'exerciseId': 'exercise-1', 'setId': 'set-1', 'reps': 9},
      ],
    });

    controller.detach(ownerToken);

    expect(controller.pending.value, isNull);
    expect(controller.getActiveWorkout()['code'], 'no_active_workout');
  });
}

WorkoutSession _session() => WorkoutSession(
  id: 'session-1',
  name: 'Push day',
  startTime: DateTime(2026, 8, 27, 9),
  exercises: [
    const WorkoutExercise(
      id: 'exercise-1',
      exercise: Exercise(
        id: 'bench-press',
        name: 'Bench Press',
        muscles: ['chest'],
      ),
      sets: [
        WorkoutSet(id: 'set-1', weight: 60, reps: 8),
        WorkoutSet(id: 'set-2', weight: 60, reps: 8, isCompleted: true),
      ],
    ),
  ],
);
