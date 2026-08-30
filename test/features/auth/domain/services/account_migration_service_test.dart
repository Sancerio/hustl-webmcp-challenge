import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/auth/domain/entities/auth_user.dart';
import 'package:hustl_app/features/auth/domain/services/account_migration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;
  late int wipeWorkouts;
  late int wipeTemplates;
  late int wipeNutrition;
  late AccountMigrationService service;

  AuthUser google(String id) => AuthUser(id: id, provider: AuthProvider.google);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
    wipeWorkouts = 0;
    wipeTemplates = 0;
    wipeNutrition = 0;
    service = AccountMigrationService(
      preferences: prefs,
      wipeLocalWorkouts: () async => wipeWorkouts++,
      wipeLocalTemplates: () async => wipeTemplates++,
      wipeNutrition: () async => wipeNutrition++,
    );
  });

  group('guest → new account upgrade', () {
    test('resets cursors, keeps local store, records the account', () async {
      // Stale cursors that must be reset so the account's server history pulls.
      await prefs.setWorkoutsSyncVersion(7);
      await prefs.setWorkoutsLastSyncAt(DateTime(2026, 1, 1));
      await prefs.setWorkoutsUploadOffset(3);
      await prefs.setWorkoutsUploadSignature('a|b|c');
      await prefs.setTemplatesSyncVersion(5);
      await prefs.setTemplatesLastSyncAt(DateTime(2026, 1, 1));

      final result = await service.onAuthenticated(google('userA'));

      expect(result, AccountMigration.guestUpgrade);
      // Cursors reset → the next sync re-pulls the full server history.
      expect(await prefs.getWorkoutsSyncVersion(), 0);
      expect(await prefs.getWorkoutsLastSyncAt(), isNull);
      expect(await prefs.getWorkoutsUploadOffset(), 0);
      expect(await prefs.getWorkoutsUploadSignature(), isNull);
      expect(await prefs.getTemplatesSyncVersion(), 0);
      expect(await prefs.getTemplatesLastSyncAt(), isNull);
      // Local store KEPT (the dirty guest rows upload = the merge).
      expect(wipeWorkouts, 0);
      expect(wipeTemplates, 0);
      // Account recorded for future switch detection.
      expect(await prefs.getAuthLastUserId(), 'userA');
    });
  });

  group('guest → existing account with server history', () {
    test('resets cursor so a (mocked) sync pulls the full history', () async {
      // The existing account's history lives on the server; the upgrade only has
      // to reset the cursor so a sync pulls it. We don't run a real sync here —
      // asserting the reset is the contract that lets the mocked sync re-pull.
      await prefs.setWorkoutsSyncVersion(42); // a prior, stale cursor

      final result = await service.onAuthenticated(google('userA'));

      expect(result, AccountMigration.guestUpgrade);
      expect(await prefs.getWorkoutsSyncVersion(), 0); // full re-pull next sync
      expect(await prefs.getWorkoutsLastSyncAt(), isNull);
      // Guest's local rows are kept so they merge-upload alongside the pull.
      expect(wipeWorkouts, 0);
      expect(await prefs.getAuthLastUserId(), 'userA');
    });
  });

  group('account switch wipes the prior account', () {
    test('direct switch (A→B) wipes local + clears all sync state', () async {
      await service.onAuthenticated(google('A')); // links A
      // Seed A-state that must be cleared so B can't see/upload it.
      await prefs.setWorkoutsSyncVersion(9);
      await prefs.setTemplatesSyncVersion(4);
      await prefs.addWorkoutsDeletedId('x');

      final result = await service.onAuthenticated(google('B'));

      expect(result, AccountMigration.accountSwitch);
      expect(wipeWorkouts, 1);
      expect(wipeTemplates, 1);
      expect(wipeNutrition, 1);
      expect(await prefs.getWorkoutsSyncVersion(), 0);
      expect(await prefs.getTemplatesSyncVersion(), 0);
      expect(await prefs.getWorkoutsDeletedIds(), isEmpty);
      expect(await prefs.getAuthLastUserId(), 'B');
    });

    test('reports a failed wipe and never records the new account', () async {
      await service.onAuthenticated(google('A'));
      final failingService = AccountMigrationService(
        preferences: prefs,
        wipeLocalWorkouts: () async => throw StateError('disk unavailable'),
        wipeLocalTemplates: () async => wipeTemplates++,
        wipeNutrition: () async => wipeNutrition++,
      );

      final result = await failingService.onAuthenticated(google('B'));

      expect(result, AccountMigration.failed);
      expect(await prefs.getAuthLastUserId(), 'A');
      expect(wipeTemplates, 1);
      expect(wipeNutrition, 1);
    });

    test('A → sign out → B never inherits A local data', () async {
      await service.onAuthenticated(google('A')); // links A

      final out = await service.onUnauthenticated(); // sign out
      expect(out, AccountMigration.signOut);
      expect(wipeWorkouts, 1); // A's local wiped at sign-out
      expect(wipeTemplates, 1);
      expect(wipeNutrition, 1); // the nutrition offline queue is cleared too
      expect(await prefs.getAuthLastUserId(), isNull);

      final result = await service.onAuthenticated(google('B')); // B signs in
      // After the sign-out wipe, B looks like a fresh upgrade onto a clean store.
      expect(result, AccountMigration.guestUpgrade);
      expect(wipeWorkouts, 1); // no extra wipe needed (store already clean)
      expect(await prefs.getWorkoutsSyncVersion(), 0); // cursors reset for pull
      expect(await prefs.getAuthLastUserId(), 'B');
    });
  });

  group('safety guards', () {
    test(
      'same account re-auth is a no-op (no wipe, cursor preserved)',
      () async {
        await service.onAuthenticated(google('A'));
        await prefs.setWorkoutsSyncVersion(11); // synced since the upgrade

        final result = await service.onAuthenticated(google('A'));

        expect(result, AccountMigration.none);
        expect(wipeWorkouts, 0);
        expect(
          await prefs.getWorkoutsSyncVersion(),
          11,
        ); // preserved, no re-pull
      },
    );

    test('pure-guest sign-out never wipes guest local data', () async {
      final result = await service.onUnauthenticated();
      expect(result, AccountMigration.none);
      expect(wipeWorkouts, 0);
      expect(wipeTemplates, 0);
    });

    test('guest-provider authentication is a no-op', () async {
      final result = await service.onAuthenticated(
        const AuthUser(id: 'guest', provider: AuthProvider.guest),
      );
      expect(result, AccountMigration.none);
      expect(await prefs.getAuthLastUserId(), isNull);
      expect(wipeWorkouts, 0);
      expect(wipeTemplates, 0);
    });
  });
}
