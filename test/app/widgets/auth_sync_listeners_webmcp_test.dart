import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/di/service_locator.dart';
import 'package:hustl_app/app/widgets/auth_sync_listeners.dart';
import 'package:hustl_app/core/webmcp/web_mcp_access_gate.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/services/account_migration_service.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hustl_app/features/workout_logging/data/services/workout_sync_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

class _MockAccountMigrationService extends Mock
    implements AccountMigrationService {}

class _MockWorkoutSyncService extends Mock implements WorkoutSyncService {}

void main() {
  late StreamController<AuthState> states;
  late _MockAuthBloc authBloc;
  late WebMcpAccessGate gate;
  late PreferencesService preferences;

  setUpAll(() {
    registerFallbackValue(
      const AuthUser(id: 'fallback', provider: AuthProvider.guest),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService();
    preferences.resetForTests();
    await preferences.init();
    states = StreamController<AuthState>.broadcast();
    authBloc = _MockAuthBloc();
    gate = WebMcpAccessGate();
    when(() => authBloc.stream).thenAnswer((_) => states.stream);
    when(() => authBloc.state).thenReturn(AuthHydrating());
    getIt.registerSingleton<WebMcpAccessGate>(gate);
    getIt.registerSingleton<PreferencesService>(preferences);
  });

  tearDown(() async {
    await states.close();
    await getIt.reset();
  });

  testWidgets('opens for a settled guest and closes during auth loading', (
    tester,
  ) async {
    await tester.pumpWidget(_app(authBloc));

    states.add(AuthUnauthenticated());
    await tester.pump();
    await tester.pump();
    expect(gate.ready.value, isTrue);

    states.add(AuthLoading());
    await tester.pump();
    expect(gate.ready.value, isFalse);
  });

  testWidgets(
    'stays closed on an unauthenticated outage for a linked account',
    (tester) async {
      await preferences.setAuthLastUserId('user-1');
      await tester.pumpWidget(_app(authBloc));

      states.add(AuthUnauthenticated());
      await tester.pump();
      await tester.pump();

      expect(gate.ready.value, isFalse);
    },
  );

  testWidgets('stays closed until authenticated account migration settles', (
    tester,
  ) async {
    final migration = _MockAccountMigrationService();
    final completed = Completer<AccountMigration>();
    when(
      () => migration.onAuthenticated(any()),
    ).thenAnswer((_) => completed.future);
    getIt.registerSingleton<AccountMigrationService>(migration);
    await tester.pumpWidget(_app(authBloc));

    states.add(
      const AuthAuthenticated(
        AuthUser(
          id: 'user-1',
          email: 'athlete@example.com',
          provider: AuthProvider.google,
        ),
      ),
    );
    await tester.pump();
    expect(gate.ready.value, isFalse);

    completed.complete(AccountMigration.none);
    await tester.pump();
    expect(gate.ready.value, isTrue);
  });

  testWidgets('stale migration completion cannot reopen a newer transition', (
    tester,
  ) async {
    final migration = _MockAccountMigrationService();
    final completed = Completer<AccountMigration>();
    when(
      () => migration.onAuthenticated(any()),
    ).thenAnswer((_) => completed.future);
    getIt.registerSingleton<AccountMigrationService>(migration);
    await tester.pumpWidget(_app(authBloc));

    states.add(
      const AuthAuthenticated(
        AuthUser(id: 'user-1', provider: AuthProvider.google),
      ),
    );
    await tester.pump();
    states.add(AuthLoading());
    await tester.pump();

    completed.complete(AccountMigration.none);
    await tester.pump();
    expect(gate.ready.value, isFalse);
  });

  testWidgets('reported migration failure leaves WebMCP closed', (
    tester,
  ) async {
    final migration = _MockAccountMigrationService();
    final workoutSync = _MockWorkoutSyncService();
    when(
      () => migration.onAuthenticated(any()),
    ).thenAnswer((_) async => AccountMigration.failed);
    getIt.registerSingleton<AccountMigrationService>(migration);
    getIt.registerSingleton<WorkoutSyncService>(workoutSync);
    await tester.pumpWidget(_app(authBloc));

    states.add(
      const AuthAuthenticated(
        AuthUser(id: 'user-1', provider: AuthProvider.google),
      ),
    );
    await tester.pump();

    expect(gate.ready.value, isFalse);
    verifyNoMoreInteractions(workoutSync);
  });

  testWidgets('challenge mode opens WebMCP but never starts post-auth sync', (
    tester,
  ) async {
    final migration = _MockAccountMigrationService();
    final workoutSync = _MockWorkoutSyncService();
    when(
      () => migration.onAuthenticated(any()),
    ).thenAnswer((_) async => AccountMigration.none);
    getIt.registerSingleton<AccountMigrationService>(migration);
    getIt.registerSingleton<WorkoutSyncService>(workoutSync);
    await tester.pumpWidget(_app(authBloc, challengeMode: true));

    states.add(
      const AuthAuthenticated(
        AuthUser(id: 'demo-user', provider: AuthProvider.google),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(gate.ready.value, isTrue);
    verify(() => migration.onAuthenticated(any())).called(1);
    verifyNoMoreInteractions(workoutSync);
  });
}

Widget _app(AuthBloc authBloc, {bool challengeMode = false}) => MaterialApp(
  home: BlocProvider<AuthBloc>.value(
    value: authBloc,
    child: AuthSyncListeners(
      challengeMode: challengeMode,
      child: const Text('app'),
    ),
  ),
);
