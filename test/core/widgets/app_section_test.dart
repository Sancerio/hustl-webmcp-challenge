import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/widgets/app_section.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('SectionHeader renders sentence-case in the 17/w700 voice', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SectionHeader('This week')));

    // Displayed in natural sentence case (not uppercased).
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsNothing);

    final text = tester.widget<Text>(find.text('This week'));
    expect(text.style?.fontSize, 17);
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
  });

  testWidgets('SectionHeader announces the natural-case title as a header', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(const SectionHeader('This week')));

    final node = tester.getSemantics(find.bySemanticsLabel('This week'));
    expect(node, matchesSemantics(label: 'This week', isHeader: true));

    handle.dispose();
  });

  testWidgets('SectionHeader places an optional trailing widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SectionHeader(
          'Training',
          trailing: TextButton(onPressed: () {}, child: const Text('See all')),
        ),
      ),
    );

    expect(find.text('Training'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('SectionList separates children with hairline dividers, '
      'no card chrome', (tester) async {
    await tester.pumpWidget(
      _host(
        const SectionList(
          children: [Text('Row 1'), Text('Row 2'), Text('Row 3')],
        ),
      ),
    );

    // n-1 hairlines between n children.
    expect(
      find.descendant(
        of: find.byType(SectionList),
        matching: find.byType(Divider),
      ),
      findsNWidgets(2),
    );

    // Flat: no Card and no decorated container around the group.
    expect(
      find.descendant(
        of: find.byType(SectionList),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
  });

  testWidgets('SectionList can omit dividers', (tester) async {
    await tester.pumpWidget(
      _host(
        const SectionList(
          dividers: false,
          children: [Text('Row 1'), Text('Row 2')],
        ),
      ),
    );

    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('AppSection composes header + flat list', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppSection(
          title: 'Insights',
          children: [Text('Row 1'), Text('Row 2')],
        ),
      ),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('SectionList card mode wraps the group in a surface card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SectionList(card: true, children: [Text('Row 1'), Text('Row 2')]),
      ),
    );

    // Card mode still separates with hairlines, and now has a decorated
    // container wrapping the group.
    expect(find.text('Row 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SectionList),
        matching: find.byType(Container),
      ),
      findsWidgets,
    );
  });
}
