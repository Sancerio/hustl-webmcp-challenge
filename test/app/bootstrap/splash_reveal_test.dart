import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/bootstrap/splash_reveal.dart';

void main() {
  testWidgets('shows the icon and wordmark, then completes and tears down', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(home: SplashReveal(onCompleted: () => completed = true)),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(SplashReveal.wordmark), findsOneWidget);
    expect(completed, isFalse);

    await tester.pumpAndSettle();

    expect(completed, isTrue);
    // Fully dissolved: the overlay renders nothing hit-testable.
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('snaps straight to completed when animations are disabled', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SplashReveal(onCompleted: () => completed = true),
        ),
      ),
    );
    await tester.pump();

    expect(completed, isTrue);
  });
}
