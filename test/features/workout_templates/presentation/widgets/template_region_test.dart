import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_log/domain/models/muscle_group.dart';
import 'package:hustl_app/features/workout_templates/presentation/widgets/template_region.dart';

void main() {
  group('dominantTemplateRegion', () {
    test('push / pull / legs / core resolve to their own region', () {
      expect(
        dominantTemplateRegion(
          {MuscleGroup.middlePecs, MuscleGroup.triceps, MuscleGroup.frontDelts},
        ),
        TemplateRegion.push,
      );
      expect(
        dominantTemplateRegion(
          {MuscleGroup.lats, MuscleGroup.biceps, MuscleGroup.rhomboids},
        ),
        TemplateRegion.pull,
      );
      expect(
        dominantTemplateRegion(
          {MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.hamstrings},
        ),
        TemplateRegion.legs,
      );
      expect(
        dominantTemplateRegion({MuscleGroup.upperAbs, MuscleGroup.obliques}),
        TemplateRegion.core,
      );
    });

    test('empty input resolves to null', () {
      expect(dominantTemplateRegion(const {}), isNull);
    });

    test('picks the region with the most groups', () {
      expect(
        dominantTemplateRegion(
          {MuscleGroup.middlePecs, MuscleGroup.triceps, MuscleGroup.quads},
        ),
        TemplateRegion.push,
      );
    });
  });

  group('templateRegionColor', () {
    test('push, pull and legs get distinct tints', () {
      const scheme = ColorScheme.dark();
      final tints = {
        templateRegionColor(TemplateRegion.push, scheme),
        templateRegionColor(TemplateRegion.pull, scheme),
        templateRegionColor(TemplateRegion.legs, scheme),
      };
      expect(tints.length, 3);
    });
  });
}
