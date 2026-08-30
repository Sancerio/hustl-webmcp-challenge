import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/app/navigation/app_router.dart' show navigatorKey;
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/auth/presentation/widgets/account_sheet.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/onboarding/presentation/intro/onboarding_welcome_screen.dart';

/// Loads the real brand font so intrinsic text-width math in the overflow
/// test matches production metrics (the fallback test font renders wider).
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

class _GuestAuthRepository implements AuthRepository {
  @override
  Future<AuthUser?> getCurrentUser() async => null;

  @override
  Future<AuthUser> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

/// Records whether the real OS permission request was made, mirroring the
/// weight-log health-connect-primer test's fake.
class _FakeHealthMetricsRepository implements HealthMetricsRepository {
  int requestCount = 0;

  @override
  Future<HealthPermissionsStatus> requestPermissions() async {
    requestCount++;
    return const HealthPermissionsStatus(
      hasPermissions: true,
      isServiceAvailable: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Always throws from `requestPermissions`, so the "best-effort, never
/// dead-ends" contract can be exercised.
class _ThrowingHealthMetricsRepository implements HealthMetricsRepository {
  @override
  Future<HealthPermissionsStatus> requestPermissions() async {
    throw Exception('permission request failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  // Regression for a RenderFlex overflow at large Dynamic Type on a small
  // screen: the welcome body must scroll instead of overflowing once content
  // no longer fits the viewport.
  testWidgets('does not overflow at textScaler 2.0 on a 320x568 screen', (
    tester,
  ) async {
    await _loadDmSans();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(2.0),
              ),
              child: const OnboardingWelcomeScreen(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Default (non-web) hierarchy: connect-recovery is primary.
    expect(find.text('Connect recovery data'), findsOneWidget);
  });

  Future<AuthBloc> pumpWelcome(
    WidgetTester tester, {
    bool webFallback = false,
  }) async {
    final authBloc = AuthBloc(_GuestAuthRepository())
      ..add(AuthCheckRequested());
    addTearDown(authBloc.close);
    final router = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/onboarding/welcome',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('HOME'))),
        ),
        GoRoute(
          path: '/onboarding/welcome',
          builder: (context, state) =>
              OnboardingWelcomeScreen(webFallback: webFallback),
        ),
        GoRoute(
          path: '/account',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('ACCOUNT'))),
        ),
        GoRoute(
          path: '/health',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('HEALTH'))),
        ),
      ],
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return authBloc;
  }

  testWidgets(
    '"I already have an account" completes onboarding, lands home, and opens '
    'sign-in directly instead of the Account tab',
    (tester) async {
      await pumpWelcome(tester);

      // The taller trail-plan card pushes the footer link below the fold at
      // the tiny default test viewport; scroll it into view before tapping
      // (a real device's viewport is far taller than this harness default).
      await tester.ensureVisible(find.text('I already have an account'));
      await tester.tap(find.text('I already have an account'));
      // Let the guest auth check resolve and the sheet's entrance animation
      // settle without relying on pumpAndSettle (the skeleton state ticks a
      // repeating shimmer while auth is still hydrating).
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final prefs = GetIt.instance<PreferencesService>();
      expect(prefs.onboardingIntroSeen, isTrue);

      // Landed home, not on the Account tab.
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsNothing);

      // The real sign-in sheet is open directly — no extra tap required.
      expect(find.byType(AccountSheet), findsOneWidget);
    },
  );

  testWidgets('"Connect recovery data" marks intro + primer seen, requests OS '
      'permissions, and lands on Health', (tester) async {
    final repo = _FakeHealthMetricsRepository();
    GetIt.instance.registerSingleton<HealthMetricsRepository>(repo);

    await pumpWelcome(tester);

    await tester.ensureVisible(find.text('Connect recovery data'));
    await tester.tap(find.text('Connect recovery data'));
    await tester.pumpAndSettle();

    final prefs = GetIt.instance<PreferencesService>();
    expect(prefs.onboardingIntroSeen, isTrue);
    expect(prefs.seenHealthConnectPrimer, isTrue);
    expect(repo.requestCount, 1);

    expect(find.text('HEALTH'), findsOneWidget);
  });

  testWidgets(
    'a thrown permission request still completes onboarding and navigates '
    'to Health (best-effort, never dead-ends)',
    (tester) async {
      GetIt.instance.registerSingleton<HealthMetricsRepository>(
        _ThrowingHealthMetricsRepository(),
      );

      await pumpWelcome(tester);

      await tester.ensureVisible(find.text('Connect recovery data'));
      await tester.tap(find.text('Connect recovery data'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final prefs = GetIt.instance<PreferencesService>();
      expect(prefs.onboardingIntroSeen, isTrue);
      expect(prefs.seenHealthConnectPrimer, isTrue);
      expect(find.text('HEALTH'), findsOneWidget);
    },
  );

  testWidgets(
    'web fallback shows the start-first hierarchy and hides the recovery '
    'waypoint',
    (tester) async {
      await pumpWelcome(tester, webFallback: true);

      expect(find.text('Start your first workout'), findsOneWidget);
      expect(find.text('Bring your Strong history'), findsOneWidget);
      expect(find.text('Connect recovery data'), findsNothing);
      expect(find.text('Start a workout first'), findsNothing);
      // The trail-plan card's recovery waypoint is hidden entirely.
      expect(find.text('Connect recovery'), findsNothing);
    },
  );
}
