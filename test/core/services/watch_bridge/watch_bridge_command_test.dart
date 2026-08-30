import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/services/watch_bridge/watch_bridge_command.dart';

void main() {
  group('WatchCommand.tryParse', () {
    test('parses discard_workout into discardWorkout', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-1',
        'type': 'discard_workout',
        'sessionId': 's1',
      });

      expect(command, isNotNull);
      expect(command!.type, WatchCommandType.discardWorkout);
      expect(command.sessionId, 's1');
    });

    test('still parses end_workout into endWorkout (unchanged)', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-2',
        'type': 'end_workout',
        'sessionId': 's1',
      });

      expect(command, isNotNull);
      expect(command!.type, WatchCommandType.endWorkout);
    });

    test('parses add_set into addSet with target exercise', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-add-set',
        'type': 'add_set',
        'sessionId': 's1',
        'exerciseId': 'ex-123',
      });

      expect(command, isNotNull);
      expect(command!.type, WatchCommandType.addSet);
      expect(command.sessionId, 's1');
      expect(command.exerciseId, 'ex-123');
    });

    test('returns null for an unknown type', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-3',
        'type': 'not_a_real_command',
      });

      expect(command, isNull);
    });

    test('parses an extended add_exercise carrying a named exercise', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-add',
        'type': 'add_exercise',
        'sessionId': 's1',
        'exerciseId': 'ex-123',
        'exerciseName': 'Pull Up',
        'exerciseSlug': 'pull-up',
      });

      expect(command, isNotNull);
      expect(command!.type, WatchCommandType.addExercise);
      expect(command.sessionId, 's1');
      expect(command.exerciseId, 'ex-123');
      expect(command.exerciseName, 'Pull Up');
      expect(command.exerciseSlug, 'pull-up');
    });

    test(
      'parses a blank add_exercise (no name) for the legacy empty-state add',
      () {
        final command = WatchCommand.tryParse({
          'id': 'cmd-add-blank',
          'type': 'add_exercise',
          'sessionId': 's1',
        });

        expect(command, isNotNull);
        expect(command!.type, WatchCommandType.addExercise);
        expect(command.exerciseName, isNull);
        expect(command.exerciseSlug, isNull);
      },
    );

    test('parses exercise_catalog_request with a search query', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-cat',
        'type': 'exercise_catalog_request',
        'searchQuery': 'press',
      });

      expect(command, isNotNull);
      expect(command!.type, WatchCommandType.exerciseCatalogRequest);
      expect(command.searchQuery, 'press');
    });

    test('parses exercise_catalog_request without a query', () {
      final command = WatchCommand.tryParse({
        'id': 'cmd-cat-2',
        'type': 'exercise_catalog_request',
      });

      expect(command, isNotNull);
      expect(command!.type, WatchCommandType.exerciseCatalogRequest);
      expect(command.searchQuery, isNull);
    });
  });

  group('WatchSessionSet.tryParse', () {
    test('preserves explicit incomplete set state', () {
      final set = WatchSessionSet.tryParse({
        'weight': 2.5,
        'reps': 300,
        'isCompleted': false,
      });

      expect(set, isNotNull);
      expect(set!.weight, 2.5);
      expect(set.reps, 300);
      expect(set.isCompleted, isFalse);
      expect(set.completedAtMs, isNull);
    });

    test('defaults legacy watch session sets to completed', () {
      final set = WatchSessionSet.tryParse({'weight': 60, 'reps': 8});

      expect(set, isNotNull);
      expect(set!.isCompleted, isTrue);
    });
  });
}
