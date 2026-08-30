import '../../features/workout_templates/domain/models/workout_template.dart';
import '../../features/workout_templates/domain/repositories/template_repository.dart';

/// Deterministic in-memory [TemplateRepository] for demo mode.
///
/// Seeds Alex's primary "Chest Power" routine (the one favorite template the
/// persona reaches for) plus a couple of starter templates so the Templates
/// surface is populated. Template exercises follow the Map shape the UI reads:
/// `{exerciseId, sets, restTimerSeconds}`.
class DemoTemplateRepository implements TemplateRepository {
  DemoTemplateRepository({required DateTime anchor})
    : _templates = _seed(anchor);

  final Map<String, WorkoutTemplate> _templates;

  static Map<String, WorkoutTemplate> _seed(DateTime anchor) {
    final created = anchor.subtract(const Duration(days: 84));
    final updated = anchor.subtract(const Duration(days: 2));
    final templates = <WorkoutTemplate>[
      WorkoutTemplate(
        id: 'demo-template-push',
        name: 'Chest Power',
        description:
            'Chest, shoulders and triceps — Alex\'s go-to push session.',
        createdAt: created,
        updatedAt: updated,
        exercises: const [
          {
            'exerciseId': 'Barbell Bench Press',
            'sets': 4,
            'restTimerSeconds': 150,
          },
          {
            'exerciseId': 'Incline Dumbbell Press',
            'sets': 3,
            'restTimerSeconds': 120,
          },
          {'exerciseId': 'Overhead Press', 'sets': 3, 'restTimerSeconds': 120},
          {
            'exerciseId': 'Dumbbell Lateral Raise',
            'sets': 3,
            'restTimerSeconds': 75,
          },
          {
            'exerciseId': 'Cable Triceps Pushdown',
            'sets': 3,
            'restTimerSeconds': 75,
          },
        ],
      ),
      WorkoutTemplate(
        id: 'demo-template-pull',
        name: 'Pull Power',
        description: 'Back and biceps with a heavy deadlift opener.',
        createdAt: created,
        updatedAt: updated,
        exercises: const [
          {
            'exerciseId': 'Barbell Deadlift',
            'sets': 3,
            'restTimerSeconds': 180,
          },
          {
            'exerciseId': 'Weighted Pull-up',
            'sets': 4,
            'restTimerSeconds': 120,
          },
          {'exerciseId': 'Barbell Row', 'sets': 3, 'restTimerSeconds': 120},
          {'exerciseId': 'Lat Pulldown', 'sets': 3, 'restTimerSeconds': 90},
          {'exerciseId': 'Barbell Curl', 'sets': 3, 'restTimerSeconds': 75},
        ],
      ),
      WorkoutTemplate(
        id: 'demo-template-legs',
        name: 'Leg Power',
        description: 'Quad-focused with hamstring and calf accessories.',
        createdAt: created,
        updatedAt: updated,
        exercises: const [
          {
            'exerciseId': 'Barbell Back Squat',
            'sets': 4,
            'restTimerSeconds': 180,
          },
          {'exerciseId': 'Leg Press', 'sets': 3, 'restTimerSeconds': 120},
          {'exerciseId': 'Leg Extension', 'sets': 3, 'restTimerSeconds': 75},
          {
            'exerciseId': 'Romanian Deadlift',
            'sets': 3,
            'restTimerSeconds': 120,
          },
          {
            'exerciseId': 'Standing Calf Raise',
            'sets': 3,
            'restTimerSeconds': 60,
          },
        ],
      ),
    ];
    return {for (final t in templates) t.id: t};
  }

  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async {
    final list = _templates.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async {
    return _templates[id];
  }

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    _templates[template.id] = template;
    return template;
  }

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    _templates[template.id] = template;
    return template;
  }

  @override
  Future<void> deleteWorkoutTemplate(String id) async {
    _templates.remove(id);
  }
}
