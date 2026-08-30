import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge.dart';

/// Renders the [EffortReserveGauge] colour ramp + an in-context Exercise
/// History chip to PNGs, in both light and dark theme.
///
///   flutter test --no-pub --update-goldens \
///     test/features/workout_logging/presentation/widgets/effort/effort_reserve_gauge_golden_test.dart
class _GaugeHarness extends StatelessWidget {
  const _GaugeHarness();

  // rpe 10..4 maps to RIR 0..6 (6 clamps "6+").
  static const _rpes = <int>[10, 9, 8, 7, 6, 5, 4];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('RIR ramp', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final rpe in _rpes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        'rpe $rpe',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    EffortReserveGauge(rpe: rpe),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Exercise history chip',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '22.5 kg × 12',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(width: 8),
                  const EffortReserveGauge(rpe: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<void> pumpHarness(WidgetTester tester, ThemeData theme) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(420 * 2, 620 * 2);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(body: _GaugeHarness()),
      ),
    );
    await tester.pump();
  }

  testWidgets('effort reserve gauge — light', (tester) async {
    await pumpHarness(tester, AppTheme.lightTheme);

    await expectLater(
      find.byType(_GaugeHarness),
      matchesGoldenFile('goldens/effort_reserve_gauge_light.png'),
    );
  });

  testWidgets('effort reserve gauge — dark', (tester) async {
    await pumpHarness(tester, AppTheme.darkTheme);

    await expectLater(
      find.byType(_GaugeHarness),
      matchesGoldenFile('goldens/effort_reserve_gauge_dark.png'),
    );
  });
}
