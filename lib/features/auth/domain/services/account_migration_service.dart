import 'dart:developer' as dev;

import '../../../../core/services/preferences_service.dart';
import '../../../onboarding/domain/onboarding_telemetry.dart';
import '../entities/auth_user.dart';

/// The data-migration action applied for an auth transition. Returned so the
/// caller can value-time a post-link confirmation only when something happened.
enum AccountMigration {
  /// Nothing to do: a guest stayed a guest, or the same real account
  /// re-authenticated (e.g. a cold-start session rehydrate).
  none,

  /// A true guest upgraded to a real account. The local store is KEPT (the dirty
  /// guest rows upload = the merge) and the sync cursors are RESET so the
  /// account's existing server history is pulled in full.
  guestUpgrade,

  /// Signed into a DIFFERENT real account than last time. The local store and all
  /// sync cursors are WIPED so account B never shows or uploads account A's data.
  accountSwitch,

  /// Explicit sign-out / lost session for a previously-linked real account. The
  /// local store and all sync cursors are WIPED.
  signOut,

  /// At least one required isolation step failed. Callers must keep any
  /// account-scoped read surface closed until a later transition succeeds.
  failed,
}

/// Migrates local workout/template data safely across guest→account upgrades,
/// account switches, and sign-out.
///
/// Hooked into the auth flow ([AuthSyncListeners]): [onAuthenticated] runs BEFORE
/// the post-login sync so the cursor reset / wipe takes effect before any
/// push/pull, and [onUnauthenticated] runs on a definitive sign-out.
///
/// Every step is best-effort and idempotent and never throws into the auth flow.
/// Failures are reported as [AccountMigration.failed] so privacy-sensitive
/// callers can remain closed without blocking the visible sign-in flow.
class AccountMigrationService {
  AccountMigrationService({
    required PreferencesService preferences,
    required Future<void> Function() wipeLocalWorkouts,
    required Future<void> Function() wipeLocalTemplates,
    Future<void> Function()? wipeNutrition,
  }) : _prefs = preferences,
       _wipeLocalWorkouts = wipeLocalWorkouts,
       _wipeLocalTemplates = wipeLocalTemplates,
       _wipeNutrition = wipeNutrition;

  final PreferencesService _prefs;
  final Future<void> Function() _wipeLocalWorkouts;
  final Future<void> Function() _wipeLocalTemplates;
  final Future<void> Function()? _wipeNutrition;

  /// Hook for [AuthAuthenticated]. MUST run BEFORE the post-login sync.
  ///
  /// - Guest provider (defensive): no-op — never touch local data, never record
  ///   it as the last real account.
  /// - No prior real account on this device (`auth_last_user_id == null`): a true
  ///   guest→account upgrade. KEEP the local store (dirty guest rows upload) and
  ///   RESET the workout + template sync cursors so the account's server history
  ///   pulls in full. Records the new account as `auth_last_user_id`.
  /// - A different real account (`auth_last_user_id != user.id`): WIPE the local
  ///   store + all sync cursors so the new account can't see/upload the prior
  ///   account's data. Records the new account as `auth_last_user_id`.
  /// - The same real account re-authenticating: no-op.
  Future<AccountMigration> onAuthenticated(AuthUser user) async {
    try {
      if (user.isGuest) return AccountMigration.none;

      final lastUserId = await _prefs.getAuthLastUserId();

      if (lastUserId == null) {
        await _resetSyncCursors();
        await _prefs.setAuthLastUserId(user.id);
        OnboardingTelemetry.instance.migrationApplied('guestUpgrade');
        return AccountMigration.guestUpgrade;
      }

      if (lastUserId != user.id) {
        if (!await _wipeAllLocalData()) return AccountMigration.failed;
        await _prefs.setAuthLastUserId(user.id);
        OnboardingTelemetry.instance.migrationApplied('accountSwitch');
        return AccountMigration.accountSwitch;
      }

      return AccountMigration.none;
    } catch (e, st) {
      dev.log(
        'AccountMigrationService.onAuthenticated failed',
        error: e,
        stackTrace: st,
      );
      return AccountMigration.failed;
    }
  }

  /// Hook for a DEFINITIVE [AuthUnauthenticated] (explicit sign-out or a lost
  /// session). Wipes the local store + sync cursors ONLY when a real account was
  /// previously linked (`auth_last_user_id != null`) — so a pure guest's local
  /// data is never touched on a normal cold start (a guest is unauthenticated).
  ///
  /// The caller must NOT invoke this for the transient `AuthHydrating` /
  /// `AuthLoading` states that precede authentication, or a re-authenticating
  /// real user (and a signing-in guest's local rows) would be wiped.
  Future<AccountMigration> onUnauthenticated() async {
    try {
      final lastUserId = await _prefs.getAuthLastUserId();
      if (lastUserId == null) return AccountMigration.none;
      if (!await _wipeAllLocalData()) return AccountMigration.failed;
      await _prefs.clearAuthLastUserId();
      OnboardingTelemetry.instance.migrationApplied('signOut');
      return AccountMigration.signOut;
    } catch (e, st) {
      dev.log(
        'AccountMigrationService.onUnauthenticated failed',
        error: e,
        stackTrace: st,
      );
      return AccountMigration.failed;
    }
  }

  Future<void> _resetSyncCursors() async {
    await _prefs.resetWorkoutSyncCursors();
    await _prefs.resetTemplateSyncCursors();
    OnboardingTelemetry.instance.syncCursorReset('workoutsAndTemplates');
  }

  Future<bool> _wipeAllLocalData() async {
    // Each step is independently guarded so one failure can't strand the rest.
    final results = <bool>[
      await _runBestEffort(_wipeLocalWorkouts, 'wipe local workouts'),
      await _runBestEffort(_wipeLocalTemplates, 'wipe local templates'),
      await _runBestEffort(
        _prefs.clearWorkoutSyncState,
        'clear workout sync state',
      ),
      await _runBestEffort(
        _prefs.clearTemplateSyncState,
        'clear template sync state',
      ),
    ];
    // Clear the nutrition offline queue so a departing user's queued food-log
    // ops can't later upload under a different account.
    final wipeNutrition = _wipeNutrition;
    if (wipeNutrition != null) {
      results.add(
        await _runBestEffort(wipeNutrition, 'wipe nutrition offline queue'),
      );
    }
    return results.every((succeeded) => succeeded);
  }

  Future<bool> _runBestEffort(
    Future<void> Function() step,
    String label,
  ) async {
    try {
      await step();
      return true;
    } catch (e, st) {
      dev.log(
        'AccountMigrationService: $label failed',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }
}
