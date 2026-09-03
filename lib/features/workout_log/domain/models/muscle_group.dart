/// Granular muscle group taxonomy for detailed body composition tracking.
/// Expands from 6 high-level regions to 27 anatomically specific muscle groups.
enum MuscleGroup {
  // Chest (3)
  upperPecs,
  middlePecs,
  lowerPecs,

  // Back (5)
  lats,
  upperTraps,
  lowerTraps,
  rhomboids,
  lowerBack,

  // Shoulders (3)
  frontDelts,
  sideDelts,
  rearDelts,

  // Arms (3)
  biceps,
  triceps,
  forearms,

  // Core (3)
  upperAbs,
  lowerAbs,
  obliques,

  // Legs (7)
  quads,
  hamstrings,
  glutes,
  calves,
  hipAbductors,
  hipAdductors,
  hipFlexors,

  // Other (3)
  neck,
  other,
  fullBody,
}

/// High-level display regions used for UI aggregation and radar chart visualization.
/// Maps 27 granular muscle groups to 6 broad categories for readability.
enum DisplayRegion { chest, back, shoulders, arms, core, legs, other }

extension MuscleGroupLabel on MuscleGroup {
  /// Human-readable labels for UI display.
  String get label {
    switch (this) {
      // Chest
      case MuscleGroup.upperPecs:
        return 'Upper Pecs';
      case MuscleGroup.middlePecs:
        return 'Middle Pecs';
      case MuscleGroup.lowerPecs:
        return 'Lower Pecs';

      // Back
      case MuscleGroup.lats:
        return 'Lats';
      case MuscleGroup.upperTraps:
        return 'Upper Traps';
      case MuscleGroup.lowerTraps:
        return 'Lower Traps';
      case MuscleGroup.rhomboids:
        return 'Rhomboids';
      case MuscleGroup.lowerBack:
        return 'Lower Back';

      // Shoulders
      case MuscleGroup.frontDelts:
        return 'Front Delts';
      case MuscleGroup.sideDelts:
        return 'Side Delts';
      case MuscleGroup.rearDelts:
        return 'Rear Delts';

      // Arms
      case MuscleGroup.biceps:
        return 'Biceps';
      case MuscleGroup.triceps:
        return 'Triceps';
      case MuscleGroup.forearms:
        return 'Forearms';

      // Core
      case MuscleGroup.upperAbs:
        return 'Upper Abs';
      case MuscleGroup.lowerAbs:
        return 'Lower Abs';
      case MuscleGroup.obliques:
        return 'Obliques';

      // Legs
      case MuscleGroup.quads:
        return 'Quads';
      case MuscleGroup.hamstrings:
        return 'Hamstrings';
      case MuscleGroup.glutes:
        return 'Glutes';
      case MuscleGroup.calves:
        return 'Calves';
      case MuscleGroup.hipAbductors:
        return 'Hip Abductors';
      case MuscleGroup.hipAdductors:
        return 'Hip Adductors';
      case MuscleGroup.hipFlexors:
        return 'Hip Flexors';

      // Other
      case MuscleGroup.neck:
        return 'Neck';
      case MuscleGroup.other:
        return 'Other';
      case MuscleGroup.fullBody:
        return 'Full Body';
    }
  }

  /// Stable identifier for storage and API interoperability.
  String get key {
    switch (this) {
      // Chest
      case MuscleGroup.upperPecs:
        return 'upper_pecs';
      case MuscleGroup.middlePecs:
        return 'middle_pecs';
      case MuscleGroup.lowerPecs:
        return 'lower_pecs';

      // Back
      case MuscleGroup.lats:
        return 'lats';
      case MuscleGroup.upperTraps:
        return 'upper_traps';
      case MuscleGroup.lowerTraps:
        return 'lower_traps';
      case MuscleGroup.rhomboids:
        return 'rhomboids';
      case MuscleGroup.lowerBack:
        return 'lower_back';

      // Shoulders
      case MuscleGroup.frontDelts:
        return 'front_delts';
      case MuscleGroup.sideDelts:
        return 'side_delts';
      case MuscleGroup.rearDelts:
        return 'rear_delts';

      // Arms
      case MuscleGroup.biceps:
        return 'biceps';
      case MuscleGroup.triceps:
        return 'triceps';
      case MuscleGroup.forearms:
        return 'forearms';

      // Core
      case MuscleGroup.upperAbs:
        return 'upper_abs';
      case MuscleGroup.lowerAbs:
        return 'lower_abs';
      case MuscleGroup.obliques:
        return 'obliques';

      // Legs
      case MuscleGroup.quads:
        return 'quads';
      case MuscleGroup.hamstrings:
        return 'hamstrings';
      case MuscleGroup.glutes:
        return 'glutes';
      case MuscleGroup.calves:
        return 'calves';
      case MuscleGroup.hipAbductors:
        return 'hip_abductors';
      case MuscleGroup.hipAdductors:
        return 'hip_adductors';
      case MuscleGroup.hipFlexors:
        return 'hip_flexors';

      // Other
      case MuscleGroup.neck:
        return 'neck';
      case MuscleGroup.other:
        return 'other';
      case MuscleGroup.fullBody:
        return 'full_body';
    }
  }
}

extension MuscleGroupAggregation on MuscleGroup {
  /// Maps granular muscle groups to high-level display regions for UI aggregation.
  DisplayRegion get displayRegion {
    switch (this) {
      // Chest
      case MuscleGroup.upperPecs:
      case MuscleGroup.middlePecs:
      case MuscleGroup.lowerPecs:
        return DisplayRegion.chest;

      // Back
      case MuscleGroup.lats:
      case MuscleGroup.upperTraps:
      case MuscleGroup.lowerTraps:
      case MuscleGroup.rhomboids:
      case MuscleGroup.lowerBack:
        return DisplayRegion.back;

      // Shoulders
      case MuscleGroup.frontDelts:
      case MuscleGroup.sideDelts:
      case MuscleGroup.rearDelts:
        return DisplayRegion.shoulders;

      // Arms
      case MuscleGroup.biceps:
      case MuscleGroup.triceps:
      case MuscleGroup.forearms:
        return DisplayRegion.arms;

      // Core
      case MuscleGroup.upperAbs:
      case MuscleGroup.lowerAbs:
      case MuscleGroup.obliques:
        return DisplayRegion.core;

      // Legs
      case MuscleGroup.quads:
      case MuscleGroup.hamstrings:
      case MuscleGroup.glutes:
      case MuscleGroup.calves:
      case MuscleGroup.hipAbductors:
      case MuscleGroup.hipAdductors:
      case MuscleGroup.hipFlexors:
        return DisplayRegion.legs;

      // Other
      case MuscleGroup.neck:
      case MuscleGroup.other:
      case MuscleGroup.fullBody:
        return DisplayRegion.other;
    }
  }

  /// Maps muscle groups to SVG element IDs for heat map rendering.
  String get svgRegionKey {
    switch (this) {
      // Chest
      case MuscleGroup.upperPecs:
        return 'upper_pecs';
      case MuscleGroup.middlePecs:
        return 'middle_pecs';
      case MuscleGroup.lowerPecs:
        return 'lower_pecs';

      // Back
      case MuscleGroup.lats:
        return 'lats';
      case MuscleGroup.upperTraps:
        return 'upper_traps';
      case MuscleGroup.lowerTraps:
        return 'lower_traps';
      case MuscleGroup.rhomboids:
        return 'rhomboids';
      case MuscleGroup.lowerBack:
        return 'lower_back';

      // Shoulders
      case MuscleGroup.frontDelts:
        return 'front_delts';
      case MuscleGroup.sideDelts:
        return 'side_delts';
      case MuscleGroup.rearDelts:
        return 'rear_delts';

      // Arms
      case MuscleGroup.biceps:
        return 'biceps';
      case MuscleGroup.triceps:
        return 'triceps';
      case MuscleGroup.forearms:
        return 'forearms';

      // Core
      case MuscleGroup.upperAbs:
        return 'upper_abs';
      case MuscleGroup.lowerAbs:
        return 'lower_abs';
      case MuscleGroup.obliques:
        return 'obliques';

      // Legs
      case MuscleGroup.quads:
        return 'quads';
      case MuscleGroup.hamstrings:
        return 'hamstrings';
      case MuscleGroup.glutes:
        return 'glutes';
      case MuscleGroup.calves:
        return 'calves';
      case MuscleGroup.hipAbductors:
        return 'hip_abductors';
      case MuscleGroup.hipAdductors:
        return 'hip_adductors';
      case MuscleGroup.hipFlexors:
        return 'hip_flexors';

      // Other
      case MuscleGroup.neck:
        return 'neck';
      case MuscleGroup.other:
        return 'other';
      case MuscleGroup.fullBody:
        return 'full_body';
    }
  }
}

extension DisplayRegionLabel on DisplayRegion {
  /// Human-readable labels for display regions.
  String get label {
    switch (this) {
      case DisplayRegion.chest:
        return 'Chest';
      case DisplayRegion.back:
        return 'Back';
      case DisplayRegion.shoulders:
        return 'Shoulders';
      case DisplayRegion.arms:
        return 'Arms';
      case DisplayRegion.core:
        return 'Core';
      case DisplayRegion.legs:
        return 'Legs';
      case DisplayRegion.other:
        return 'Other';
    }
  }

  /// Storage key for display regions.
  String get key {
    switch (this) {
      case DisplayRegion.chest:
        return 'chest';
      case DisplayRegion.back:
        return 'back';
      case DisplayRegion.shoulders:
        return 'shoulders';
      case DisplayRegion.arms:
        return 'arms';
      case DisplayRegion.core:
        return 'core';
      case DisplayRegion.legs:
        return 'legs';
      case DisplayRegion.other:
        return 'other';
    }
  }
}

/// Parses a [DisplayRegion] from a storage key (e.g. values emitted by routes).
DisplayRegion? displayRegionFromKey(String value) {
  switch (value.toLowerCase()) {
    case 'chest':
      return DisplayRegion.chest;
    case 'back':
      return DisplayRegion.back;
    case 'shoulders':
      return DisplayRegion.shoulders;
    case 'arms':
      return DisplayRegion.arms;
    case 'core':
      return DisplayRegion.core;
    case 'legs':
      return DisplayRegion.legs;
    case 'other':
      return DisplayRegion.other;
  }
  return null;
}

/// Parses a [MuscleGroup] from a storage key (e.g. values emitted by APIs).
MuscleGroup? muscleGroupFromKey(String value) {
  switch (value.toLowerCase()) {
    // Chest
    case 'upper_pecs':
    case 'upperpecs':
      return MuscleGroup.upperPecs;
    case 'middle_pecs':
    case 'middlepecs':
      return MuscleGroup.middlePecs;
    case 'lower_pecs':
    case 'lowerpecs':
      return MuscleGroup.lowerPecs;

    // Back
    case 'lats':
      return MuscleGroup.lats;
    case 'upper_traps':
    case 'uppertraps':
      return MuscleGroup.upperTraps;
    case 'lower_traps':
    case 'lowertraps':
      return MuscleGroup.lowerTraps;
    case 'rhomboids':
      return MuscleGroup.rhomboids;
    case 'lower_back':
    case 'lowerback':
      return MuscleGroup.lowerBack;

    // Shoulders
    case 'front_delts':
    case 'frontdelts':
      return MuscleGroup.frontDelts;
    case 'side_delts':
    case 'sidedelts':
    case 'lateral_delts':
    case 'lateraldelts':
      return MuscleGroup.sideDelts;
    case 'rear_delts':
    case 'reardelts':
      return MuscleGroup.rearDelts;

    // Arms
    case 'biceps':
      return MuscleGroup.biceps;
    case 'triceps':
      return MuscleGroup.triceps;
    case 'forearms':
      return MuscleGroup.forearms;

    // Core
    case 'upper_abs':
    case 'upperabs':
      return MuscleGroup.upperAbs;
    case 'lower_abs':
    case 'lowerabs':
      return MuscleGroup.lowerAbs;
    case 'obliques':
      return MuscleGroup.obliques;

    // Legs
    case 'quads':
    case 'quadriceps':
      return MuscleGroup.quads;
    case 'hamstrings':
      return MuscleGroup.hamstrings;
    case 'glutes':
    case 'gluteus':
      return MuscleGroup.glutes;
    case 'calves':
      return MuscleGroup.calves;
    case 'hip_abductors':
    case 'hipabductors':
    case 'hip_abductor':
    case 'hipabductor':
      return MuscleGroup.hipAbductors;
    case 'hip_adductors':
    case 'hipadductors':
    case 'hip_adductor':
    case 'hipadductor':
      return MuscleGroup.hipAdductors;
    case 'hip_flexors':
    case 'hipflexors':
      return MuscleGroup.hipFlexors;

    // Other
    case 'neck':
      return MuscleGroup.neck;
    case 'other':
      return MuscleGroup.other;
    case 'full_body':
    case 'fullbody':
      return MuscleGroup.fullBody;
  }
  return null;
}

/// Default weekly volume targets for each muscle group (in sets).
/// Total: 60 sets/week, distributed based on muscle size and training frequency.
const Map<MuscleGroup, double> defaultWeeklyTargetsByMuscleGroup = {
  // Chest (10 sets total)
  MuscleGroup.upperPecs: 4.0,
  MuscleGroup.middlePecs: 4.0,
  MuscleGroup.lowerPecs: 2.0,

  // Back (10 sets total)
  MuscleGroup.lats: 4.0,
  MuscleGroup.upperTraps: 2.0,
  MuscleGroup.lowerTraps: 1.5,
  MuscleGroup.rhomboids: 1.5,
  MuscleGroup.lowerBack: 1.0,

  // Shoulders (10 sets total)
  MuscleGroup.frontDelts: 3.0,
  MuscleGroup.sideDelts: 4.0,
  MuscleGroup.rearDelts: 3.0,

  // Arms (10 sets total)
  MuscleGroup.biceps: 4.0,
  MuscleGroup.triceps: 4.0,
  MuscleGroup.forearms: 2.0,

  // Core (10 sets total)
  MuscleGroup.upperAbs: 3.5,
  MuscleGroup.lowerAbs: 3.5,
  MuscleGroup.obliques: 3.0,

  // Legs (10 sets total)
  MuscleGroup.quads: 3.0,
  MuscleGroup.hamstrings: 3.0,
  MuscleGroup.glutes: 2.25,
  MuscleGroup.calves: 1.0,
  MuscleGroup.hipAbductors: 0.25,
  MuscleGroup.hipAdductors: 0.25,
  MuscleGroup.hipFlexors: 0.25,

  // Other (10 sets total)
  MuscleGroup.neck: 1.0,
  MuscleGroup.other: 3.0,
  MuscleGroup.fullBody: 6.0,
};
