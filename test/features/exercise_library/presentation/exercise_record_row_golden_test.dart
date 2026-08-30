import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge.dart';

/// Mirrors the Exercise Record tab's per-session row layout in
/// `exercise_detail_screen.dart` (`_ExerciseRecordTab`, records list ~line
/// 1114): a leading PR trophy, a date, the best-set summary, the
/// [EffortReserveGauge] (new), and an optional trailing "1RM ..." label.
/// Kept as a small harness (rather than mounting the full tab, which needs a
/// live `WorkoutRepository`/`ExerciseRecordService`) so the golden stays fast
/// and focused on the row layout that changed. Includes a narrow (360px)
/// width to confirm the added gauge doesn't overflow alongside the 1RM label.
class _RecordRowHarness extends StatelessWidget {
  const _RecordRowHarness();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget row({
      required bool isPr,
      required String dateStr,
      required String summary,
      int? rpe,
      String? oneRmStr,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            if (isPr) ...[
              Icon(Icons.emoji_events, color: colorScheme.primary, size: 16),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(dateStr, style: theme.textTheme.bodyMedium)),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (rpe != null) EffortReserveGauge(rpe: rpe),
                  if (oneRmStr != null)
                    Text(
                      '1RM $oneRmStr',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            row(
              isPr: true,
              dateStr: 'Jul 9, 2026',
              summary: '100 kg × 5',
              rpe: 8,
              oneRmStr: '112.5',
            ),
            const Divider(),
            row(isPr: false, dateStr: 'Jul 2, 2026', summary: '95 kg × 5'),
            const Divider(),
            row(
              isPr: false,
              dateStr: 'Jun 25, 2026',
              summary: '90 kg × 5',
              rpe: 10,
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<void> pumpHarness(
    WidgetTester tester,
    ThemeData theme, {
    double width = 420,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(width * 2, 400 * 2);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(body: _RecordRowHarness()),
      ),
    );
    await tester.pump();
  }

  testWidgets('exercise record rows with effort gauge — light', (tester) async {
    await pumpHarness(tester, AppTheme.lightTheme);

    await expectLater(
      find.byType(_RecordRowHarness),
      matchesGoldenFile('goldens/exercise_record_row_light.png'),
    );
  });

  testWidgets('exercise record rows with effort gauge — dark', (tester) async {
    await pumpHarness(tester, AppTheme.darkTheme);

    await expectLater(
      find.byType(_RecordRowHarness),
      matchesGoldenFile('goldens/exercise_record_row_dark.png'),
    );
  });

  testWidgets(
    'exercise record rows with effort gauge on a narrow phone width do not overflow',
    (tester) async {
      await pumpHarness(tester, AppTheme.lightTheme, width: 360);

      // A RenderFlex overflow throws during layout/paint — surfacing as a
      // FlutterError caught by the test framework. Absence of exceptions
      // confirms the added gauge fits alongside the PR/1RM trailing content.
      expect(tester.takeException(), isNull);
    },
  );
}
