import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/app_chip.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('renders label and optional data value', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppChip(
          label: 'Volume',
          value: '12.4k kg',
          variant: AppChipVariant.data,
        ),
      ),
    );

    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('12.4k kg'), findsOneWidget);
  });

  testWidgets('filter chip reports selected state in semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        AppChip(
          label: 'Chest',
          variant: AppChipVariant.filter,
          selected: true,
          onTap: () {},
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(AppChip));
    expect(
      node,
      matchesSemantics(
        label: 'Chest',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppChip(
          label: 'Filter',
          variant: AppChipVariant.filter,
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('status chip without onTap is not a button', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(const AppChip(label: 'Over budget')));

    final node = tester.getSemantics(find.byType(AppChip));
    expect(node, matchesSemantics(label: 'Over budget'));

    handle.dispose();
  });

  testWidgets('renders a leading icon when provided', (tester) async {
    await tester.pumpWidget(
      _host(const AppChip(label: 'Rest', icon: Icons.bedtime)),
    );

    expect(find.byIcon(Icons.bedtime), findsOneWidget);
  });

  testWidgets('shows tooltip on long-press when tooltip param is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppChip(label: 'Chest', tooltip: 'Chest region score')),
    );

    // Long-press should trigger the Tooltip overlay.
    await tester.longPress(find.byType(AppChip));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Chest region score'), findsOneWidget);
  });

  testWidgets('no tooltip widget present when tooltip param is omitted', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppChip(label: 'Chest')));

    expect(find.byType(Tooltip), findsNothing);
  });
}
