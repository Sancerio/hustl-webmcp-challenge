import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/template_web_mcp_service.dart';
import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';

WorkoutTemplate _template(List<Object?> exercises) => WorkoutTemplate(
  id: 'template-a',
  name: 'Push day',
  description: 'Strength focus',
  exercises: exercises,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 28),
);

void main() {
  test('normalizes a uniform template into proposal-valid context', () {
    final context = TemplateWebMcpService.normalize(
      _template([
        {
          'exerciseId': 'Bench Press',
          'slug': 'bench-press',
          'sets': 2,
          'restTimerSeconds': 120,
          'previousSets': [
            {'reps': 8, 'weight': 80.0, 'rpe': 8, 'setType': 'regular'},
            {'reps': 8, 'weight': 80.0, 'rpe': 8, 'setType': 'regular'},
          ],
        },
      ]),
    );

    expect(context.lossyOnEdit, isFalse);
    expect(context.plan.toJson(), {
      'name': 'Push day',
      'description': 'Strength focus',
      'exercises': [
        {
          'exerciseId': 'Bench Press',
          'slug': 'bench-press',
          'sets': 2,
          'repsTarget': 8,
          'restTimerSeconds': 120,
          'weightTarget': 80.0,
          'rpeTarget': 8,
        },
      ],
    });
    expect(context.toJson(), isNot(contains('warning')));
    expect(context.toJson()['updatedAt'], endsWith('Z'));
  });

  test('flags and bounds detail that cannot round-trip', () {
    final context = TemplateWebMcpService.normalize(
      _template([
        {
          'exerciseId': 'Assisted Pull-up',
          'sets': 25,
          'restTimerSeconds': null,
          'previousSets': [
            {'reps': 5, 'weight': -20.0, 'rpe': 7, 'setType': 'warmup'},
            {'reps': 8, 'weight': -15.0, 'rpe': 8, 'setType': 'regular'},
          ],
        },
      ]),
    );

    expect(context.lossyOnEdit, isTrue);
    expect(context.plan.exercises.single.sets, 20);
    expect(context.plan.exercises.single.restTimerSeconds, 0);
    expect(context.plan.exercises.single.weightTarget, isNull);
    expect(context.toJson()['warning'], templateNormalizationWarning);
  });

  test('placeholder targets are not silently promoted to authored targets', () {
    final context = TemplateWebMcpService.normalize(
      _template([
        {
          'exerciseId': 'Cable Row',
          'sets': 3,
          'restTimerSeconds': 90,
          'targetsArePlaceholder': true,
          'previousSets': [
            {'reps': 8, 'weight': 0.0, 'rpe': 8, 'setType': 'regular'},
          ],
        },
      ]),
    );

    final exercise = context.plan.exercises.single;
    expect(context.lossyOnEdit, isTrue);
    expect(exercise.repsTarget, isNull);
    expect(exercise.rpeTarget, isNull);
    expect(exercise.weightTarget, isNull);
  });

  test('reports an unsynced local template as non-editable', () {
    final context = TemplateWebMcpService.normalize(
      _template([
        {'exerciseId': 'Bench Press', 'sets': 3, 'restTimerSeconds': 90},
      ]),
      syncedForEdit: false,
    );

    expect(context.editable, isFalse);
    expect(context.toJson()['editUnavailableReason'], 'template_not_synced');
  });

  test('rounds fractional stored RPE and marks the edit as lossy', () {
    final context = TemplateWebMcpService.normalize(
      _template([
        {
          'exerciseId': 'Bench Press',
          'sets': 1,
          'restTimerSeconds': 120,
          'previousSets': [
            {'reps': 8, 'weight': 80.0, 'rpe': 7.5, 'setType': 'regular'},
          ],
        },
      ]),
    );

    expect(context.plan.exercises.single.rpeTarget, 8);
    expect(context.lossyOnEdit, isTrue);
  });
}
