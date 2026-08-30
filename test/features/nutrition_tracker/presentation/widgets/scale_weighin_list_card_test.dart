import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/app_section.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/scale_weighin_list_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('renders the section header and one row per weigh-in', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ScaleWeighInListCard(
          scale: const [
            {'date': '2024-06-03', 'weightKg': 71.0, 'source': 'self'},
            {'date': '2024-06-04', 'weightKg': 70.6, 'source': 'apple_health'},
            {'date': '2024-06-05', 'weightKg': 70.1, 'source': 'self'},
          ],
          sourcesByDate: const {},
          onOverrideDay: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scale weigh-ins'), findsOneWidget);
    // Grouped premium card surface.
    expect(find.byType(SectionList), findsOneWidget);
    // Tabular weight values, newest first.
    expect(find.text('70.1 kg'), findsOneWidget);
    expect(find.text('70.6 kg'), findsOneWidget);
    expect(find.text('71.0 kg'), findsOneWidget);
    // Source meta is surfaced.
    expect(find.text('Apple Health'), findsOneWidget);
  });
}
