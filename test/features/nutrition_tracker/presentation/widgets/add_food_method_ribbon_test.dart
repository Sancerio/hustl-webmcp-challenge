import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/add_food_method_ribbon.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, int> taps,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: AddFoodMethodRibbon(
          onScan: () => taps['scan'] = (taps['scan'] ?? 0) + 1,
          onQuickAdd: () => taps['quick'] = (taps['quick'] ?? 0) + 1,
          onDescribe: () => taps['describe'] = (taps['describe'] ?? 0) + 1,
          onRecipes: () => taps['recipes'] = (taps['recipes'] ?? 0) + 1,
          onCopyDay: () => taps['copy'] = (taps['copy'] ?? 0) + 1,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders all five method chips', (tester) async {
    await _pump(tester, taps: {});

    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
    expect(find.text('Describe'), findsOneWidget);
    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Copy day'), findsOneWidget);
  });

  testWidgets('each chip fires its own callback', (tester) async {
    final taps = <String, int>{};
    await _pump(tester, taps: taps);

    for (final entry in const {
      'Scan': 'scan',
      'Quick add': 'quick',
      'Describe': 'describe',
      'Recipes': 'recipes',
      'Copy day': 'copy',
    }.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pump();
      expect(taps[entry.value], 1, reason: '${entry.key} should fire once');
    }
  });
}
