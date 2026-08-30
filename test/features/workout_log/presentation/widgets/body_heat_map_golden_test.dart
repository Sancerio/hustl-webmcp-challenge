import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:hustl_app/features/workout_log/domain/services/body_score_service.dart';
import 'package:hustl_app/features/workout_log/presentation/widgets/body_heat_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String template;
  setUpAll(() async {
    template = await rootBundle.loadString(
      'assets/images/muscle-body-detailed.svg',
    );
  });

  String canonicalizeSvg(String input) {
    return input.replaceAll(RegExp(r'\s+'), '').trim();
  }

  Map<MuscleGroup, double> buildIntensities() {
    // Keep this deterministic (not tied to targets), so goldens only change
    // when the SVG template or composer logic changes.
    return {
      for (final group in MuscleGroup.values)
        group: () {
          switch (group.displayRegion) {
            case DisplayRegion.chest:
              return 0.9;
            case DisplayRegion.back:
              return 0.7;
            case DisplayRegion.shoulders:
              return 0.6;
            case DisplayRegion.arms:
              return 0.5;
            case DisplayRegion.core:
              return 0.4;
            case DisplayRegion.legs:
              return 0.8;
            case DisplayRegion.other:
              return 0.0;
          }
        }(),
    };
  }

  Future<void> expectComposerGolden({
    required ThemeData theme,
    required String fileName,
  }) async {
    final composer = MuscleSvgComposer(template);
    final svg = composer.build(intensities: buildIntensities(), theme: theme);
    final normalizedActual = canonicalizeSvg(svg);
    final goldenFile = File(
      'test/features/workout_log/presentation/widgets/goldens/$fileName',
    );
    final expected = await goldenFile.readAsString();
    final normalizedExpected = canonicalizeSvg(expected);

    if (normalizedActual != normalizedExpected) {
      final actualPath =
          'test/features/workout_log/presentation/widgets/goldens/_actual_'
          '$fileName';
      await File(actualPath).writeAsString(svg);
      fail(
        'MuscleSvgComposer output mismatch for $fileName. '
        'Compare $actualPath with the golden and update if intended.',
      );
    }
  }

  test('MuscleSvgComposer matches golden - light mode', () async {
    await expectComposerGolden(
      theme: ThemeData.light(useMaterial3: true),
      fileName: 'body_heat_map_light.svg',
    );
  });

  test('MuscleSvgComposer matches golden - dark mode', () async {
    await expectComposerGolden(
      theme: ThemeData.dark(useMaterial3: true),
      fileName: 'body_heat_map_dark.svg',
    );
  });

  testWidgets('BodyHeatMap summary highlights dominant regions', (
    tester,
  ) async {
    Map<MuscleGroup, BodyRegionMetrics> buildMetrics({
      double chest = 0,
      double back = 0,
      double shoulders = 0,
      double arms = 0,
      double core = 0,
      double legs = 0,
    }) {
      return {
        MuscleGroup.middlePecs: BodyRegionMetrics(
          volume: chest,
          sets: 0,
          minutes: 0,
        ),
        MuscleGroup.lats: BodyRegionMetrics(volume: back, sets: 0, minutes: 0),
        MuscleGroup.sideDelts: BodyRegionMetrics(
          volume: shoulders,
          sets: 0,
          minutes: 0,
        ),
        MuscleGroup.biceps: BodyRegionMetrics(
          volume: arms,
          sets: 0,
          minutes: 0,
        ),
        MuscleGroup.upperAbs: BodyRegionMetrics(
          volume: core,
          sets: 0,
          minutes: 0,
        ),
        MuscleGroup.quads: BodyRegionMetrics(volume: legs, sets: 0, minutes: 0),
        for (final group in MuscleGroup.values)
          if (!{
            MuscleGroup.middlePecs,
            MuscleGroup.lats,
            MuscleGroup.sideDelts,
            MuscleGroup.biceps,
            MuscleGroup.upperAbs,
            MuscleGroup.quads,
          }.contains(group))
            group: BodyRegionMetrics.zero,
      };
    }

    final metrics = buildMetrics(chest: 120, legs: 60, shoulders: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 420,
                child: BodyHeatMap(
                  metricsByStrategy: {
                    for (final strategy in BodyScoreStrategies.defaults)
                      strategy.id: metrics,
                  },
                  strategies: BodyScoreStrategies.defaults,
                  weeklyTargetsByStrategy: {
                    for (final strategy in BodyScoreStrategies.defaults)
                      strategy.id: Map<MuscleGroup, double>.from(
                        defaultWeeklyTargetsByMuscleGroup,
                      ),
                  },
                  breakdown: {
                    for (final group in MuscleGroup.values)
                      group: <String, double>{},
                  },
                  templateOverride: template,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final summaryFinder = find.byWidgetPredicate((widget) {
      return widget is Text &&
          widget.data != null &&
          widget.data!.contains('trained most');
    });
    expect(summaryFinder, findsOneWidget);
    final summaryText = tester.widget<Text>(summaryFinder).data!;
    expect(summaryText, contains('Last 28 days'));
    expect(summaryText, contains('trained most'));
    expect(summaryText, contains('needs more'));
  });

  test(
    'MuscleSvgComposer colors data-region templates on non-<g> elements',
    () {
      const legacyLikeTemplate = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <path data-region="front-chest" fill="#cbd5dc" fill-opacity="0.3" d="M0 0 H10 V10 H0 Z" />
</svg>
''';
      final composer = MuscleSvgComposer(legacyLikeTemplate);
      final svg = composer.build(
        intensities: {for (final group in MuscleGroup.values) group: 0.0},
        displayRegionIntensities: const {DisplayRegion.chest: 1.0},
        theme: ThemeData.light(useMaterial3: true),
      );

      final doc = XmlDocument.parse(svg);
      final chestElement = doc.descendants.whereType<XmlElement>().firstWhere(
        (el) => el.getAttribute('data-region') == 'front-chest',
      );

      final fill = chestElement.getAttribute('fill');
      final fillOpacity = chestElement.getAttribute('fill-opacity');
      expect(fill, isNotNull);
      expect(fill, isNot('#cbd5dc'));
      expect(fillOpacity, isNotNull);
      expect(double.parse(fillOpacity!), greaterThan(0.2));
    },
  );
}
