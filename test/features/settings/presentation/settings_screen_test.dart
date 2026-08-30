import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hustl_app/features/auth/presentation/widgets/account_sheet.dart';
import 'package:go_router/go_router.dart';

import 'package:hustl_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/services/theme_service.dart';
import 'package:hustl_app/core/navigation/current_route_service.dart';
import 'package:hustl_app/features/workout_logging/domain/repositories/workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_exercise.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_set.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:hustl_app/features/auth/domain/services/auth_redirect_service.dart';
import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';

class _FakeWorkoutRepo implements WorkoutRepository {
  WorkoutSession _emptySession() => WorkoutSession(
    id: 's1',
    name: 'Test',
    startTime: DateTime(2024, 1, 1),
    exercises: const [],
  );

  WorkoutExercise _emptyExercise() => const WorkoutExercise(
    id: 'e1',
    exercise: Exercise(name: 'TestEx', muscles: []),
    sets: [],
  );

  @override
  Future<WorkoutSession> addExerciseToSession(
    String sessionId,
    WorkoutExercise exercise,
  ) async => _emptySession();

  @override
  Future<WorkoutExercise> addSetToExercise(
    String sessionId,
    String exerciseId,
    WorkoutSet set,
  ) async => _emptyExercise();

  @override
  Future<WorkoutSession> completeWorkoutSession(String sessionId) async =>
      _emptySession();

  @override
  Future<void> deleteWorkoutSession(String id) async => Future.value();

  @override
  Future<WorkoutSession?> getLatestActiveSession() async => Future.value(null);

  @override
  Future<List<WorkoutSet>?> getPreviousExerciseSets(
    String exerciseName, {
    String? exerciseSlug,
  }) async => Future.value(null);

  @override
  Future<WorkoutSession?> getWorkoutSession(String id) async =>
      Future.value(null);

  @override
  Future<List<WorkoutSession>> getWorkoutSessions({
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) async => Future.value([]);

  @override
  Future<void> recomputeAllPrFlags() async => Future.value();

  @override
  Future<WorkoutSession> updateExerciseInSession(
    String sessionId,
    String exerciseId,
    WorkoutExercise exercise,
  ) async => _emptySession();

  @override
  Future<WorkoutExercise> updateSetInExercise(
    String sessionId,
    String exerciseId,
    int setIndex,
    WorkoutSet set,
  ) async => _emptyExercise();

  @override
  Future<WorkoutSession> updateWorkoutSession(
    WorkoutSession session, {
    bool markDirty = true,
  }) async => session;

  @override
  Future<WorkoutSession> createWorkoutSession(WorkoutSession session) async =>
      session;

  @override
  Future<WorkoutSession> removeExerciseFromSession(
    String sessionId,
    String exerciseId,
  ) async => _emptySession();

  @override
  Future<bool> checkIfSetIsPR(
    String exerciseName,
    WorkoutSet set, {
    String? exerciseSlug,
  }) async => false;

  @override
  Future<DateTime?> getLastPerformedDate(
    String exerciseName, {
    String? exerciseSlug,
  }) async {
    return null;
  }

  @override
  Future<ExercisePr?> getExercisePr(
    String exerciseName, {
    String? exerciseSlug,
  }) async => null;
}

class _FakeWorkoutSyncService
    with WidgetsBindingObserver
    implements WorkoutSyncService {
  @override
  final ValueNotifier<SyncProgress?> progress = ValueNotifier(null);
  @override
  final ValueNotifier<List<String>> errors = ValueNotifier(<String>[]);
  @override
  final ValueNotifier<SyncStatus> status = ValueNotifier<SyncStatus>(
    SyncStatus.idle,
  );

  bool started = false;
  bool stopped = false;

  @override
  Future<void> syncNow() async {}

  @override
  Future<({List<String> errors, bool persistFailed})> importServer(
    List<Map<String, dynamic>> server,
  ) async => (errors: const <String>[], persistFailed: false);

  @override
  void startAutoSync() {
    started = true;
  }

  @override
  void stopAutoSync() {
    stopped = true;
  }

  @override
  void startAutoSyncIfNeeded() {
    // Mirror startAutoSync behavior in tests without restarting logic
    started = true;
  }

  @override
  Timer? get timer => null;

  @override
  bool get observerAttached => false;

  @override
  bool get isSyncing => false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class _FakeHealthMetricsRepository implements HealthMetricsRepository {
  HealthPermissionsStatus status = const HealthPermissionsStatus(
    hasPermissions: false,
    isServiceAvailable: true,
    deniedPermanently: false,
  );

  @override
  Future<void> clearCache() async {}

  @override
  Future<HealthSnapshot> loadSnapshot({
    required DateTime start,
    required DateTime end,
    bool forceRefresh = false,
  }) async {
    return HealthSnapshot(
      rangeStart: start,
      rangeEnd: end,
      metrics: const [],
      nutritionEntries: const [],
      dailySummaries: const [],
      recoverySnapshots: const [],
      lastSyncedAt: start,
      warnings: const [],
    );
  }

  @override
  Future<HealthPermissionsStatus> getPermissionsStatus() async => status;

  @override
  Future<HealthPermissionsStatus> requestPermissions() async {
    status = const HealthPermissionsStatus(
      hasPermissions: true,
      isServiceAvailable: true,
      deniedPermanently: false,
    );
    return status;
  }

  @override
  Future<void> resetPermissionDenialFlag() async {}

  @override
  Future<HealthProviderAvailability> getProviderAvailability() async =>
      HealthProviderAvailability.available;

  @override
  Future<void> installHealthConnect() async {}
}

Future<void> _pumpSettingsScreen(WidgetTester tester, AuthBloc authBloc) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/health', builder: (context, state) => const SizedBox()),
    ],
  );

  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'hustl',
      packageName: 'hustl',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'sig',
    );
  });
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Hustl',
      packageName: 'com.example.hustl',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: 'sig',
    );
    await GetIt.instance.reset(dispose: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();
    GetIt.instance.registerSingleton<PreferencesService>(prefs);
    final themeService = ThemeService(prefs);
    await themeService.init();
    GetIt.instance.registerSingleton<ThemeService>(themeService);
    GetIt.instance.registerSingleton<WorkoutRepository>(_FakeWorkoutRepo());
    GetIt.instance.registerSingleton<WorkoutSyncService>(
      _FakeWorkoutSyncService(),
    );
    GetIt.instance.registerLazySingleton<AuthRedirectService>(
      () => AuthRedirectService(),
    );
    GetIt.instance.registerSingleton<HealthMetricsRepository>(
      _FakeHealthMetricsRepository(),
    );
    // Needed by showLoginSheet(), which reads the current route before opening.
    GetIt.instance.registerSingleton<CurrentRouteService>(
      CurrentRouteService(),
    );
  });

  testWidgets('shows progress indicator when syncing', (tester) async {
    final fakeAuthRepo = _AuthedAuthRepo();
    final authBloc = AuthBloc(fakeAuthRepo)..add(AuthCheckRequested());
    final syncService =
        GetIt.instance<WorkoutSyncService>() as _FakeWorkoutSyncService;
    syncService.progress.value = const SyncProgress(1, 10);
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    expect(find.text('Syncing 1/10'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final btnFinder = find.widgetWithText(FilledButton, 'Syncing...');
    expect(btnFinder, findsOneWidget);
    final btn = tester.widget<FilledButton>(btnFinder);
    expect(btn.onPressed, isNull);
  });

  testWidgets('shows haptic toggle on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final authBloc = AuthBloc(_AuthedAuthRepo())..add(AuthCheckRequested());
      await _pumpSettingsScreen(tester, authBloc);
      await tester.pump();
      expect(find.text('Haptic feedback'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('allows configuring inactivity reminder duration', (
    tester,
  ) async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setInactivityReminderMinutes(10);

    final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final dropdownFinder = find.byKey(const Key('inactivityDurationDropdown'));
    await tester.dragUntilVisible(
      dropdownFinder,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final dropdown = tester.widget<DropdownButton<int>>(dropdownFinder);
    expect(dropdown.value, 10);

    await tester.tap(dropdownFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('15 minutes').last, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(prefs.inactivityReminderMinutes, 15);
  });

  testWidgets('allows disabling auto watch heart-rate recording', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final prefs = GetIt.instance<PreferencesService>();
      final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
      await _pumpSettingsScreen(tester, authBloc);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tileTitle = find.text('Auto-record heart rate on Apple Watch');
      await tester.scrollUntilVisible(tileTitle, 300);
      final tile = find.ancestor(
        of: tileTitle,
        matching: find.byType(ListTile),
      );
      final toggle = find.descendant(of: tile, matching: find.byType(Switch));

      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(await prefs.getWatchHeartRateRecordingEnabled(), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('toggles showing workouts from other apps in the day', (
    tester,
  ) async {
    final prefs = GetIt.instance<PreferencesService>();
    final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Defaults ON.
    expect(await prefs.getShowExternalWorkoutsInDay(), isTrue);

    final tileTitle = find.text('Show workouts from other apps in your day');
    await tester.scrollUntilVisible(tileTitle, 300);
    final tile = find.ancestor(of: tileTitle, matching: find.byType(ListTile));
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));

    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isTrue);

    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await prefs.getShowExternalWorkoutsInDay(), isFalse);
  });

  testWidgets('hides haptic toggle on non-mobile platforms', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final authBloc = AuthBloc(_AuthedAuthRepo())..add(AuthCheckRequested());
      await _pumpSettingsScreen(tester, authBloc);
      await tester.pump();
      expect(find.text('Haptic feedback'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('displays app version number', (tester) async {
    final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(find.textContaining('Version'), 300);
    expect(find.textContaining('Version'), findsOneWidget);
  });

  testWidgets('opens sign-in sheet from settings', (tester) async {
    final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.byType(AccountSheet), findsOneWidget);
  });

  testWidgets('reveals debug toggle after tapping version 5 times', (
    tester,
  ) async {
    final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final versionFinder = find.textContaining('Version');
    await tester.scrollUntilVisible(versionFinder, 300);
    // Pull the footer fully into view so the tap target isn't clipped at the
    // bottom edge (the list grew once Data sources was added under Legal).
    await tester.ensureVisible(versionFinder);
    await tester.pump();
    expect(find.text('Enable debug mode'), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.tap(versionFinder);
      await tester.pump();
    }
    expect(find.text('Enable debug mode'), findsOneWidget);
  });

  testWidgets('shows Data sources entry and opens ODbL attribution', (
    tester,
  ) async {
    final authBloc = AuthBloc(_FakeAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final entry = find.text('Data sources');
    await tester.scrollUntilVisible(entry, 300);
    expect(entry, findsOneWidget);

    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Branded food data from Open Food Facts (ODbL). '
        'Generic foods from USDA FoodData Central (public domain).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows profile picture when authenticated', (tester) async {
    final authBloc = AuthBloc(_AuthedAuthRepo())..add(AuthCheckRequested());
    await _pumpSettingsScreen(tester, authBloc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final signedInTile = find.widgetWithText(ListTile, 'Signed in');
    expect(signedInTile, findsOneWidget);
    expect(
      find.descendant(of: signedInTile, matching: find.byType(CircleAvatar)),
      findsOneWidget,
    );
  });
}

class _FakeAuthRepo implements AuthRepository {
  @override
  Future<AuthUser?> getCurrentUser() async => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<AuthUser> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) {
    throw UnimplementedError();
  }
}

class _AuthedAuthRepo implements AuthRepository {
  @override
  Future<AuthUser?> getCurrentUser() async =>
      const AuthUser(id: '1', provider: AuthProvider.google);

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<AuthUser> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? fullName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> signInWithGoogle() {
    throw UnimplementedError();
  }
}
