import 'package:hustl_app/features/workout_templates/domain/models/workout_template.dart';
import 'package:hustl_app/features/workout_templates/domain/repositories/template_repository.dart';

class TemplateRepositoryFake implements TemplateRepository {
  final Map<String, WorkoutTemplate> _store = {};

  @override
  Future<WorkoutTemplate> createWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    _store[template.id] = template;
    return template;
  }

  @override
  Future<void> deleteWorkoutTemplate(String id) async {
    _store.remove(id);
  }

  @override
  Future<WorkoutTemplate?> getWorkoutTemplate(String id) async {
    return _store[id];
  }

  @override
  Future<List<WorkoutTemplate>> getWorkoutTemplates() async {
    return _store.values.toList();
  }

  @override
  Future<WorkoutTemplate> updateWorkoutTemplate(
    WorkoutTemplate template,
  ) async {
    _store[template.id] = template;
    return template;
  }
}
