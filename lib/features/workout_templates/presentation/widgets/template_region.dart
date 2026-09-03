import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';

/// A broad training region used to colour a template's leading holder so
/// routines (push / pull / legs / core) are distinct at a glance.
enum TemplateRegion { push, pull, legs, core, full }

TemplateRegion _regionForGroup(MuscleGroup group) {
  switch (group) {
    case MuscleGroup.upperPecs:
    case MuscleGroup.middlePecs:
    case MuscleGroup.lowerPecs:
    case MuscleGroup.frontDelts:
    case MuscleGroup.sideDelts:
    case MuscleGroup.rearDelts:
    case MuscleGroup.triceps:
      return TemplateRegion.push;
    case MuscleGroup.lats:
    case MuscleGroup.upperTraps:
    case MuscleGroup.lowerTraps:
    case MuscleGroup.rhomboids:
    case MuscleGroup.lowerBack:
    case MuscleGroup.biceps:
    case MuscleGroup.forearms:
      return TemplateRegion.pull;
    case MuscleGroup.quads:
    case MuscleGroup.hamstrings:
    case MuscleGroup.glutes:
    case MuscleGroup.calves:
    case MuscleGroup.hipAbductors:
    case MuscleGroup.hipAdductors:
    case MuscleGroup.hipFlexors:
      return TemplateRegion.legs;
    case MuscleGroup.upperAbs:
    case MuscleGroup.lowerAbs:
    case MuscleGroup.obliques:
      return TemplateRegion.core;
    case MuscleGroup.neck:
    case MuscleGroup.fullBody:
    case MuscleGroup.other:
      return TemplateRegion.full;
  }
}

/// The most-trained muscle group across a template's worked muscle groups, or null when
/// nothing resolves (→ a neutral fallback). Because a push day touches several
/// push-region groups (chest, delts, triceps), the deduped set already weights
/// toward the right region; ties fall back to a stable priority order.
TemplateRegion? dominantTemplateRegion(Iterable<MuscleGroup> groups) {
  final counts = <TemplateRegion, int>{};
  for (final group in groups) {
    final region = _regionForGroup(group);
    counts[region] = (counts[region] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;

  // Stable tiebreak: prefer the more "characteristic" region of a split.
  const priority = [
    TemplateRegion.legs,
    TemplateRegion.pull,
    TemplateRegion.push,
    TemplateRegion.core,
    TemplateRegion.full,
  ];
  TemplateRegion best = priority.first;
  var bestCount = -1;
  for (final region in priority) {
    final count = counts[region] ?? 0;
    if (count > bestCount) {
      best = region;
      bestCount = count;
    }
  }
  return bestCount > 0 ? best : null;
}

/// A violet accent for pull routines. Defined here as a deliberate category
/// colour (like the macro palette) since the shared accents collapse purple
/// onto blue.
const Color _pullViolet = Color(0xFF8B5CF6);

/// A calm holder tint per region. Push / pull / legs are clearly distinct;
/// core stays green and full-body / unknown reads neutral.
Color templateRegionColor(TemplateRegion? region, ColorScheme colors) {
  switch (region) {
    case TemplateRegion.push:
      return AppColors.accentElectricBlue;
    case TemplateRegion.pull:
      return _pullViolet;
    case TemplateRegion.legs:
      return AppColors.accentWarningAmber;
    case TemplateRegion.core:
      return AppColors.accentEmeraldGreen;
    case TemplateRegion.full:
      return colors.onSurfaceVariant;
    case null:
      return colors.onSurfaceVariant;
  }
}
