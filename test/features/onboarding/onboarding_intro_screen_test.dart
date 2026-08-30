import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/onboarding/presentation/intro/onboarding_intro_screen.dart';
import 'package:hustl_app/features/onboarding/presentation/intro/onboarding_welcome_screen.dart';

/// Renders the production onboarding intro + welcome. Update goldens with:
///   flutter test --no-pub --update-goldens \
///     test/features/onboarding/onboarding_intro_screen_test.dart
Future<void> _loadDmSans() async {
  final loader = FontLoader('DM Sans');
  for (final f in const [
    'DMSans-Regular',
    'DMSans-Medium',
    'DMSans-SemiBold',
    'DMSans-Bold',
  ]) {
    loader.addFont(rootBundle.load('assets/fonts/$f.ttf'));
  }
  await loader.load();
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await _loadDmSans();
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Disable animations so the ambient halo ticker settles (and captures the
      // still premium frame) instead of spinning forever under pumpAndSettle.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: home,
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/icon/hustl-icon.png'),
      tester.element(find.byType(MaterialApp)),
    );
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('intro carousel renders and advances', (tester) async {
    await _pump(tester, const OnboardingIntroScreen());

    // Slide 1: coach.
    expect(find.text('BASE CAMP'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Keep climbing'), findsOneWidget);
    await expectLater(
      find.byType(OnboardingIntroScreen),
      matchesGoldenFile('goldens/onboarding_intro_slide1.png'),
    );

    // Drag through the camps, capturing each artifact card.
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Bench · 60 kg × 8'), findsOneWidget);
    await expectLater(
      find.byType(OnboardingIntroScreen),
      matchesGoldenFile('goldens/onboarding_intro_slide2.png'),
    );

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chicken & rice bowl'), findsOneWidget);
    await expectLater(
      find.byType(OnboardingIntroScreen),
      matchesGoldenFile('goldens/onboarding_intro_slide3.png'),
    );

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('THE PUSH'), findsOneWidget);
    expect(find.text('+2.5 kg on bench'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    await expectLater(
      find.byType(OnboardingIntroScreen),
      matchesGoldenFile('goldens/onboarding_intro_slide4.png'),
    );
  });

  testWidgets('welcome renders the connect-recovery-first CTAs', (
    tester,
  ) async {
    await _pump(tester, const OnboardingWelcomeScreen());

    expect(find.text('Connect recovery data'), findsOneWidget);
    expect(find.text('Start a workout first'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    // Import is reachable only via the trail-plan card, not a third pill.
    expect(find.text('Bring Strong history'), findsOneWidget);
    await expectLater(
      find.byType(OnboardingWelcomeScreen),
      matchesGoldenFile('goldens/onboarding_welcome.png'),
    );
  });
}
