import '../models/workout_exercise.dart';

/// The kind of grouping, derived from the number of members in a group.
///
/// - [superset]  — exactly 2 members
/// - [giantSet]  — exactly 3 members
/// - [circuit]   — 4 or more members
enum SupersetKind {
  superset,
  giantSet,
  circuit;

  /// Sentence-case display label for the group header chip.
  String get label {
    switch (this) {
      case SupersetKind.superset:
        return 'Superset';
      case SupersetKind.giantSet:
        return 'Giant set';
      case SupersetKind.circuit:
        return 'Circuit';
    }
  }

  /// Derive the kind from a member count (2 → superset, 3 → giant set, 4+ →
  /// circuit). Counts below 2 are clamped to [superset] for safety; callers
  /// should not build groups smaller than 2 members.
  static SupersetKind fromMemberCount(int count) {
    if (count <= 2) return SupersetKind.superset;
    if (count == 3) return SupersetKind.giantSet;
    return SupersetKind.circuit;
  }
}

/// An ordered superset/giant set/circuit group within a session.
///
/// Pure value type: holds the group id, its members sorted by
/// [WorkoutExercise.supersetOrder], a display [colorIndex] (the UI maps this
/// to a theme token — this is intentionally an int, not a Color), and the
/// derived [kind].
class SupersetGroup {
  final String groupId;
  final List<WorkoutExercise> members;
  final int colorIndex;
  final SupersetKind kind;

  const SupersetGroup({
    required this.groupId,
    required this.members,
    required this.colorIndex,
    required this.kind,
  });

  /// Human-readable label for the group ('Superset' / 'Giant set' / 'Circuit').
  String get label => kind.label;

  @override
  bool operator ==(Object other) =>
      other is SupersetGroup &&
      other.groupId == groupId &&
      other.colorIndex == colorIndex &&
      other.kind == kind &&
      _listEquals(other.members, members);

  @override
  int get hashCode =>
      Object.hash(groupId, colorIndex, kind, Object.hashAll(members));

  static bool _listEquals(List<WorkoutExercise> a, List<WorkoutExercise> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Pure helper for bucketing a session's flat exercise list into ordered
/// superset groups, plus small lookups the UI needs.
///
/// Grouping rule: contiguous exercises that share a non-null
/// [WorkoutExercise.supersetGroupId] form one group. Members are sorted by
/// [WorkoutExercise.supersetOrder] (nulls last, then stable by list order).
/// A "group" of a single member is not surfaced (a superset needs 2+).
class SupersetGrouping {
  /// Number of distinct accent colors the UI cycles through. The helper only
  /// returns an index in [0, paletteSize); the UI maps it to a theme token.
  static const int paletteSize = 4;

  const SupersetGrouping._();

  /// Bucket [exercises] into ordered groups of 2+ contiguous members that
  /// share a [WorkoutExercise.supersetGroupId]. Returns an empty list when
  /// nothing is grouped. The order of returned groups follows first
  /// appearance in [exercises]; [SupersetGroup.colorIndex] cycles the palette
  /// in that same order.
  static List<SupersetGroup> groupsFor(List<WorkoutExercise> exercises) {
    final groups = <SupersetGroup>[];
    var colorIndex = 0;
    var i = 0;
    while (i < exercises.length) {
      final groupId = exercises[i].supersetGroupId;
      if (groupId == null || groupId.isEmpty) {
        i++;
        continue;
      }
      // Consume the contiguous run sharing this groupId.
      final members = <WorkoutExercise>[];
      var j = i;
      while (j < exercises.length && exercises[j].supersetGroupId == groupId) {
        members.add(exercises[j]);
        j++;
      }
      if (members.length >= 2) {
        members.sort(_bySupersetOrder);
        groups.add(
          SupersetGroup(
            groupId: groupId,
            members: List.unmodifiable(members),
            colorIndex: colorIndex % paletteSize,
            kind: SupersetKind.fromMemberCount(members.length),
          ),
        );
        colorIndex++;
      }
      i = j;
    }
    return groups;
  }

  /// The group containing the exercise with [exerciseId], or null if that
  /// exercise is ungrouped / absent.
  static SupersetGroup? groupForExercise(
    List<WorkoutExercise> exercises,
    String exerciseId,
  ) {
    for (final group in groupsFor(exercises)) {
      for (final member in group.members) {
        if (member.id == exerciseId) return group;
      }
    }
    return null;
  }

  /// Whether the exercise with [exerciseId] belongs to a (2+ member) group.
  static bool isGrouped(List<WorkoutExercise> exercises, String exerciseId) {
    return groupForExercise(exercises, exerciseId) != null;
  }

  /// Member letter for a 0-based [index] within a group: 0 → 'A', 1 → 'B', …
  /// Wraps past 'Z' into 'AA', 'AB', … so arbitrarily large groups stay legible.
  static String memberLetter(int index) {
    if (index < 0) return '';
    var n = index;
    final buffer = StringBuffer();
    while (true) {
      buffer.write(String.fromCharCode(65 + (n % 26)));
      n = n ~/ 26 - 1;
      if (n < 0) break;
    }
    return buffer.toString().split('').reversed.join();
  }

  /// The id of the next member in round order after [exerciseId], wrapping
  /// from the last member back to the first. Returns null when [exerciseId]
  /// is ungrouped. For a lone-membered (degenerate) group this returns the
  /// same id.
  static String? nextMemberId(
    List<WorkoutExercise> exercises,
    String exerciseId,
  ) {
    final group = groupForExercise(exercises, exerciseId);
    if (group == null) return null;
    final idx = group.members.indexWhere((m) => m.id == exerciseId);
    if (idx < 0) return null;
    final next = (idx + 1) % group.members.length;
    return group.members[next].id;
  }

  static int _bySupersetOrder(WorkoutExercise a, WorkoutExercise b) {
    final ao = a.supersetOrder;
    final bo = b.supersetOrder;
    if (ao == null && bo == null) return 0;
    if (ao == null) return 1; // nulls last
    if (bo == null) return -1;
    return ao.compareTo(bo);
  }
}
