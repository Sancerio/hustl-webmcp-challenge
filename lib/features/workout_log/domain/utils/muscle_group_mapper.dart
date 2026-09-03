import '../models/muscle_group.dart';

/// Normalizes raw muscle names into the canonical [MuscleGroup] taxonomy used by
/// analytics. The mapper ships with aliases harvested from the shared exercise
/// catalog plus common custom exercise entries so offline/guest data stay in
/// sync with backend aggregations.
///
/// This expands on the legacy 6-region system to provide 27 granular muscle groups
/// for more detailed body composition tracking and heat map visualization.
class MuscleGroupMapper {
  MuscleGroupMapper({Map<String, MuscleGroup>? overrides})
    : _overrides = overrides == null
          ? const {}
          : overrides.map((key, value) => MapEntry(_normalizeKey(key), value));

  final Map<String, MuscleGroup> _overrides;

  /// Resolve a muscle or muscle-group name to a [MuscleGroup]. Unknown values
  /// fall back to [MuscleGroup.other]. Null/empty strings are treated as
  /// "Other" to keep aggregation stable.
  MuscleGroup groupFor(String? muscle) {
    if (muscle == null || muscle.trim().isEmpty) {
      return MuscleGroup.other;
    }
    final key = _normalizeKey(muscle);
    if (_overrides.containsKey(key)) {
      return _overrides[key]!;
    }
    return _defaultAliases[key] ?? MuscleGroup.other;
  }

  /// Whether a muscle name can be mapped without falling back to "Other".
  bool hasMapping(String muscle) {
    final key = _normalizeKey(muscle);
    return _overrides.containsKey(key) || _defaultAliases.containsKey(key);
  }

  static String _normalizeKey(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.trim().toLowerCase().codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (char.codeUnitAt(0) >= 97 && char.codeUnitAt(0) <= 122) {
        buffer.write(char);
      } else if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static const Map<String, MuscleGroup> _defaultAliases = {
    // ============================================================
    // CHEST (3 groups: upper, middle, lower pecs)
    // ============================================================
    'chest': MuscleGroup.middlePecs,
    'pecs': MuscleGroup.middlePecs,
    'pectoral': MuscleGroup.middlePecs,
    'pectorals': MuscleGroup.middlePecs,
    'pectoralismajor': MuscleGroup.middlePecs,

    // Upper chest / clavicular pecs
    'upperchest': MuscleGroup.upperPecs,
    'upperpecs': MuscleGroup.upperPecs,
    'upperpectoral': MuscleGroup.upperPecs,
    'clavicularpecs': MuscleGroup.upperPecs,
    'clavicularchest': MuscleGroup.upperPecs,
    'inclinechest': MuscleGroup.upperPecs,

    // Lower chest / sternal pecs
    'lowerchest': MuscleGroup.lowerPecs,
    'lowerpecs': MuscleGroup.lowerPecs,
    'lowerpectoral': MuscleGroup.lowerPecs,
    'sternalpecs': MuscleGroup.lowerPecs,
    'sternalchest': MuscleGroup.lowerPecs,
    'declinechest': MuscleGroup.lowerPecs,

    // ============================================================
    // BACK (5 groups: lats, upper traps, lower traps, rhomboids, lower back)
    // ============================================================
    'back': MuscleGroup.lats,

    // Latissimus dorsi
    'lats': MuscleGroup.lats,
    'lat': MuscleGroup.lats,
    'latissimus': MuscleGroup.lats,
    'latissimusdorsi': MuscleGroup.lats,
    'lateralback': MuscleGroup.lats,
    'widelats': MuscleGroup.lats,

    // Upper trapezius
    'traps': MuscleGroup.upperTraps,
    'trap': MuscleGroup.upperTraps,
    'trapezius': MuscleGroup.upperTraps,
    'uppertraps': MuscleGroup.upperTraps,
    'uppertrap': MuscleGroup.upperTraps,
    'uppertrapezius': MuscleGroup.upperTraps,
    'necktrap': MuscleGroup.upperTraps,

    // Lower trapezius
    'lowertraps': MuscleGroup.lowerTraps,
    'lowertrap': MuscleGroup.lowerTraps,
    'lowertrapezius': MuscleGroup.lowerTraps,
    'midtraps': MuscleGroup.lowerTraps,
    'midtrap': MuscleGroup.lowerTraps,
    'middletraps': MuscleGroup.lowerTraps,

    // Rhomboids
    'rhomboids': MuscleGroup.rhomboids,
    'rhomboid': MuscleGroup.rhomboids,
    'rhomboideus': MuscleGroup.rhomboids,
    'rhomboidmajor': MuscleGroup.rhomboids,
    'rhomboidminor': MuscleGroup.rhomboids,
    'midback': MuscleGroup.rhomboids,
    'middleback': MuscleGroup.rhomboids,
    'upperback': MuscleGroup.lats,

    // Lower back / erector spinae
    'lowerback': MuscleGroup.lowerBack,
    'lowback': MuscleGroup.lowerBack,
    'erectorspinae': MuscleGroup.lowerBack,
    'spinalerectors': MuscleGroup.lowerBack,
    'lumbar': MuscleGroup.lowerBack,
    'lumbarspine': MuscleGroup.lowerBack,

    // ============================================================
    // SHOULDERS (3 groups: front, side, rear delts)
    // ============================================================
    'shoulders': MuscleGroup.sideDelts,
    'shoulder': MuscleGroup.sideDelts,
    'delts': MuscleGroup.sideDelts,
    'delt': MuscleGroup.sideDelts,
    'deltoid': MuscleGroup.sideDelts,
    'deltoids': MuscleGroup.sideDelts,

    // Front deltoids / anterior
    'frontdelts': MuscleGroup.frontDelts,
    'frontdelt': MuscleGroup.frontDelts,
    'frontdeltoid': MuscleGroup.frontDelts,
    'frontdeltoids': MuscleGroup.frontDelts,
    'anteriordelts': MuscleGroup.frontDelts,
    'anteriordelt': MuscleGroup.frontDelts,
    'anteriordeltoid': MuscleGroup.frontDelts,
    'anteriordeltoids': MuscleGroup.frontDelts,
    'frontshoulder': MuscleGroup.frontDelts,
    'frontshoulders': MuscleGroup.frontDelts,

    // Side deltoids / lateral / medial
    'sidedelts': MuscleGroup.sideDelts,
    'sidedelt': MuscleGroup.sideDelts,
    'sidedeltoid': MuscleGroup.sideDelts,
    'sidedeltoids': MuscleGroup.sideDelts,
    'lateraldelts': MuscleGroup.sideDelts,
    'lateraldelt': MuscleGroup.sideDelts,
    'lateraldeltoid': MuscleGroup.sideDelts,
    'lateraldeltoids': MuscleGroup.sideDelts,
    'medialdelts': MuscleGroup.sideDelts,
    'medialdelt': MuscleGroup.sideDelts,
    'medialdeltoid': MuscleGroup.sideDelts,
    'medialdeltoids': MuscleGroup.sideDelts,
    'middleshoulders': MuscleGroup.sideDelts,
    'middleshoulder': MuscleGroup.sideDelts,

    // Rear deltoids / posterior
    'reardelts': MuscleGroup.rearDelts,
    'reardelt': MuscleGroup.rearDelts,
    'reardeltoid': MuscleGroup.rearDelts,
    'reardeltoids': MuscleGroup.rearDelts,
    'posteriordelts': MuscleGroup.rearDelts,
    'posteriordelt': MuscleGroup.rearDelts,
    'posteriordeltoid': MuscleGroup.rearDelts,
    'posteriordeltoids': MuscleGroup.rearDelts,
    'rearshoulders': MuscleGroup.rearDelts,
    'rearshoulder': MuscleGroup.rearDelts,
    'backdelts': MuscleGroup.rearDelts,

    // ============================================================
    // ARMS (3 groups: biceps, triceps, forearms)
    // ============================================================
    'arms': MuscleGroup.biceps,
    'arm': MuscleGroup.biceps,

    // Biceps
    'biceps': MuscleGroup.biceps,
    'bicep': MuscleGroup.biceps,
    'bicepsbrachii': MuscleGroup.biceps,
    'brachii': MuscleGroup.biceps,
    'bicepsbracii': MuscleGroup.biceps,
    'bis': MuscleGroup.biceps,
    'bi': MuscleGroup.biceps,
    'upperarm': MuscleGroup.biceps,
    'brachialis': MuscleGroup.biceps,
    'brachioradialis': MuscleGroup.forearms,

    // Triceps
    'triceps': MuscleGroup.triceps,
    'tricep': MuscleGroup.triceps,
    'tricepsbrachii': MuscleGroup.triceps,
    'tris': MuscleGroup.triceps,
    'tri': MuscleGroup.triceps,

    // Forearms
    'forearms': MuscleGroup.forearms,
    'forearm': MuscleGroup.forearms,
    'wristflexors': MuscleGroup.forearms,
    'wristextensors': MuscleGroup.forearms,
    'grip': MuscleGroup.forearms,
    'gripstrength': MuscleGroup.forearms,
    'wrist': MuscleGroup.forearms,
    'wrists': MuscleGroup.forearms,
    'lowerarm': MuscleGroup.forearms,
    'lowerarms': MuscleGroup.forearms,

    // ============================================================
    // CORE (3 groups: upper abs, lower abs, obliques)
    // ============================================================
    'core': MuscleGroup.upperAbs,
    'abs': MuscleGroup.upperAbs,
    'abdominals': MuscleGroup.upperAbs,
    'abdominal': MuscleGroup.upperAbs,
    'rectusabdominis': MuscleGroup.upperAbs,
    'sixpack': MuscleGroup.upperAbs,

    // Upper abs
    'upperabs': MuscleGroup.upperAbs,
    'upperabdominals': MuscleGroup.upperAbs,
    'upperabdominal': MuscleGroup.upperAbs,
    'uppercore': MuscleGroup.upperAbs,

    // Lower abs
    'lowerabs': MuscleGroup.lowerAbs,
    'lowerabdominals': MuscleGroup.lowerAbs,
    'lowerabdominal': MuscleGroup.lowerAbs,
    'lowercore': MuscleGroup.lowerAbs,

    // Obliques
    'obliques': MuscleGroup.obliques,
    'oblique': MuscleGroup.obliques,
    'externalobliques': MuscleGroup.obliques,
    'internalobliques': MuscleGroup.obliques,
    'sideabs': MuscleGroup.obliques,
    'lateralcore': MuscleGroup.obliques,
    'lateralabs': MuscleGroup.obliques,
    'transverseabdominis': MuscleGroup.obliques,
    'serratus': MuscleGroup.obliques,
    'serratusanterior': MuscleGroup.obliques,

    // ============================================================
    // LEGS (7 groups: quads, hamstrings, glutes, calves, hip abductors, hip adductors, hip flexors)
    // ============================================================
    'legs': MuscleGroup.quads,
    'leg': MuscleGroup.quads,
    'thighs': MuscleGroup.quads,
    'thigh': MuscleGroup.quads,

    // Quadriceps
    'quads': MuscleGroup.quads,
    'quad': MuscleGroup.quads,
    'quadriceps': MuscleGroup.quads,
    'quadricep': MuscleGroup.quads,
    'quadfemoris': MuscleGroup.quads,
    'vastuslateralis': MuscleGroup.quads,
    'vastusmedialis': MuscleGroup.quads,
    'vastusintermedius': MuscleGroup.quads,
    'rectusfemoris': MuscleGroup.quads,
    'frontthigh': MuscleGroup.quads,
    'frontthighs': MuscleGroup.quads,

    // Hamstrings
    'hamstrings': MuscleGroup.hamstrings,
    'hamstring': MuscleGroup.hamstrings,
    'hams': MuscleGroup.hamstrings,
    'ham': MuscleGroup.hamstrings,
    'bicepsfemoris': MuscleGroup.hamstrings,
    'semitendinosus': MuscleGroup.hamstrings,
    'semimembranosus': MuscleGroup.hamstrings,
    'rearthigh': MuscleGroup.hamstrings,
    'rearthighs': MuscleGroup.hamstrings,
    'backthigh': MuscleGroup.hamstrings,
    'backthighs': MuscleGroup.hamstrings,

    // Glutes
    'glutes': MuscleGroup.glutes,
    'glute': MuscleGroup.glutes,
    'gluteus': MuscleGroup.glutes,
    'gluteals': MuscleGroup.glutes,
    'gluteal': MuscleGroup.glutes,
    'gluteusmaximus': MuscleGroup.glutes,
    'gluteusmedius': MuscleGroup.glutes,
    'gluteusminimus': MuscleGroup.glutes,
    'butt': MuscleGroup.glutes,
    'buttocks': MuscleGroup.glutes,
    'booty': MuscleGroup.glutes,

    // Calves
    'calves': MuscleGroup.calves,
    'calf': MuscleGroup.calves,
    'gastrocnemius': MuscleGroup.calves,
    'soleus': MuscleGroup.calves,
    'lowerleg': MuscleGroup.calves,
    'lowerlegs': MuscleGroup.calves,

    // Hip abductors
    'hipabductors': MuscleGroup.hipAbductors,
    'hipabductor': MuscleGroup.hipAbductors,
    'abductors': MuscleGroup.hipAbductors,
    'abductor': MuscleGroup.hipAbductors,
    'outerthigh': MuscleGroup.hipAbductors,
    'outerthighs': MuscleGroup.hipAbductors,
    'lateralhip': MuscleGroup.hipAbductors,
    'lateralhips': MuscleGroup.hipAbductors,

    // Hip adductors
    'hipadductors': MuscleGroup.hipAdductors,
    'hipadductor': MuscleGroup.hipAdductors,
    'adductors': MuscleGroup.hipAdductors,
    'adductor': MuscleGroup.hipAdductors,
    'innerthigh': MuscleGroup.hipAdductors,
    'innerthighs': MuscleGroup.hipAdductors,
    'groin': MuscleGroup.hipAdductors,
    'adductormagnus': MuscleGroup.hipAdductors,
    'adductorlongus': MuscleGroup.hipAdductors,
    'adductorbrevis': MuscleGroup.hipAdductors,

    // Hip flexors
    'hipflexors': MuscleGroup.hipFlexors,
    'hipflexor': MuscleGroup.hipFlexors,
    'iliopsoas': MuscleGroup.hipFlexors,
    'psoas': MuscleGroup.hipFlexors,
    'iliacus': MuscleGroup.hipFlexors,
    'tfl': MuscleGroup.hipAbductors,
    'tensorfasciaelatae': MuscleGroup.hipAbductors,

    // ============================================================
    // OTHER (3 groups: neck, other, full body)
    // ============================================================

    // Neck
    'neck': MuscleGroup.neck,
    'neckflexors': MuscleGroup.neck,
    'neckextensors': MuscleGroup.neck,
    'sternocleidomastoid': MuscleGroup.neck,
    'cervical': MuscleGroup.neck,

    // Other
    'other': MuscleGroup.other,
    'general': MuscleGroup.other,
    'custom': MuscleGroup.other,
    'mobility': MuscleGroup.other,
    'flexibility': MuscleGroup.other,
    'stretch': MuscleGroup.other,
    'stretching': MuscleGroup.other,

    // Full body / compound
    'fullbody': MuscleGroup.fullBody,
    'total': MuscleGroup.fullBody,
    'totalbody': MuscleGroup.fullBody,
    'compound': MuscleGroup.fullBody,
    'wholebody': MuscleGroup.fullBody,
    'cardio': MuscleGroup.fullBody,
    'cardiovascular': MuscleGroup.fullBody,
    'hiit': MuscleGroup.fullBody,
    'conditioning': MuscleGroup.fullBody,
  };
}

/// Resolves an exercise's flat muscle labels into figure-renderable
/// [MuscleGroup]s. Handles both display labels ("Chest", "Lower Back", "Full
/// Body") and storage keys ("lower_back") by preferring the exact storage-key
/// mapping and falling back to the normalizing [MuscleGroupMapper]. Unmappable
/// values are dropped. Pure and shared by the exercise figure and the template
/// thumbnails so both highlight the same regions.
Set<MuscleGroup> figureMuscleGroups(Iterable<String> muscles) {
  final mapper = MuscleGroupMapper();
  final groups = <MuscleGroup>{};
  for (final raw in muscles) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final keyGroup = muscleGroupFromKey(trimmed);
    final figureGroup = (keyGroup != null && keyGroup != MuscleGroup.other)
        ? keyGroup
        : mapper.groupFor(trimmed);
    if (figureGroup != MuscleGroup.other) groups.add(figureGroup);
  }
  return groups;
}
