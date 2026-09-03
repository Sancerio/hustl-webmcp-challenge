import 'package:uuid/uuid.dart';

import '../models/workout_set.dart';

/// Generate [count] empty [WorkoutSet]s, preserving the [setType]
/// from [previousSets] when available.
///
/// Linked drops (`setType == SetType.dropset` with a non-null
/// `parentSetId`) are excluded from the template: a fresh seed mirrors only
/// the previous session's top-level working/warm-up/failure sets, never stray
/// drops. Copying a drop here would lose its `parentSetId`/`dropIndex` linkage
/// and produce orphan dropset rows that get counted, labelled, and rested as
/// top-level sets. Drops are recreated explicitly by the user, not seeded.
List<WorkoutSet> generateEmptySets(
  int count,
  Uuid uuid, {
  List<WorkoutSet>? previousSets,
}) {
  final template = previousSets
      ?.where((s) => s.parentSetId == null)
      .toList(growable: false);
  return List.generate(count, (index) {
    final type = (template != null && index < template.length)
        ? template[index].setType
        : SetType.regular;
    return WorkoutSet(id: uuid.v4(), weight: 0, reps: 0, setType: type);
  });
}
