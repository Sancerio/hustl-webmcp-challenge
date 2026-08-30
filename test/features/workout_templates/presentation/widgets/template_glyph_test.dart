import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_templates/presentation/widgets/template_glyph.dart';

void main() {
  group('templateGlyphAsset', () {
    test('maps distinct workout types to distinct glyphs', () {
      expect(templateGlyphAsset('HIIT Burner'), 'assets/icons/ic_flame.svg');
      expect(templateGlyphAsset('Sunday Cardio'), 'assets/icons/ic_flame.svg');
      expect(templateGlyphAsset('EMOM Circuit'), 'assets/icons/ic_timer.svg');
      expect(templateGlyphAsset('Bench Challenge'), 'assets/icons/ic_trophy.svg');
      expect(templateGlyphAsset('Core & Abs'), 'assets/icons/ic_target.svg');
      expect(templateGlyphAsset('Mobility Flow'), 'assets/icons/ic_heart.svg');
      expect(templateGlyphAsset('Full Body Blast'), 'assets/icons/nav_train.svg');
    });

    test('strength splits and unknown names fall back to the dumbbell', () {
      for (final name in const [
        'Push Day',
        'Pull Day',
        'Leg Day',
        'Upper Body',
        'Lower Body',
        'My Routine',
        '',
      ]) {
        expect(
          templateGlyphAsset(name),
          'assets/icons/ic_dumbbell.svg',
          reason: '"$name" should use the default strength glyph',
        );
      }
    });

    test('is case-insensitive', () {
      expect(templateGlyphAsset('cardio blast'), 'assets/icons/ic_flame.svg');
      expect(templateGlyphAsset('CARDIO BLAST'), 'assets/icons/ic_flame.svg');
    });

    test('short keywords match at word boundaries, not mid-word', () {
      // "run" must not fire inside "Crunch"/"Trunk" — these are core routines.
      expect(templateGlyphAsset('Crunch Abs'), 'assets/icons/ic_target.svg');
      expect(templateGlyphAsset('Trunk & Core'), 'assets/icons/ic_target.svg');
      // ...but real cardio (including plurals/suffixes) still maps to flame.
      expect(
        templateGlyphAsset('Running Intervals'),
        'assets/icons/ic_flame.svg',
      );
      expect(templateGlyphAsset('Sprint Day'), 'assets/icons/ic_flame.svg');
    });
  });
}
