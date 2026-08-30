import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/exercise_library/presentation/screens/filter_selection_screen.dart';

void main() {
  testWidgets('filter sheet exposes Abs and Obliques muscle chips', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FilterSelectionScreen()));

    expect(find.text('Abs'), findsOneWidget);
    expect(find.text('Obliques'), findsOneWidget);
  });
}
