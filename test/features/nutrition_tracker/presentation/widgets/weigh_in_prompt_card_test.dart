import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/weight_unit.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weigh_in_prompt_card.dart';

void main() {
  testWidgets('formats Last label in lb when unit is lb', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeighInPromptCard(
            onLogTap: () {},
            onDismissTap: () {},
            latestWeightKg: 80.0,
            latestWeightDate: DateTime(2024, 6, 10),
            unit: const WeightUnit('lb'),
          ),
        ),
      ),
    );

    expect(find.textContaining('176.4 lb'), findsOneWidget);
  });

  testWidgets('defaults to kg', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeighInPromptCard(
            onLogTap: () {},
            onDismissTap: () {},
            latestWeightKg: 80.0,
            latestWeightDate: DateTime(2024, 6, 10),
          ),
        ),
      ),
    );

    expect(find.textContaining('80.0 kg'), findsOneWidget);
  });
}
