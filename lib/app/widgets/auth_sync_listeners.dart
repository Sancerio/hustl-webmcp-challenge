import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/services/nutrition_widget_service.dart';
import '../../core/services/preferences_service.dart';
import '../../core/services/workout_widget_service.dart';
import '../../core/webmcp/web_mcp_access_gate.dart';
import '../../core/widgets/hustl_snack.dart';
import '../../features/ai_proposals/services/proposal_count_service.dart';
import '../../features/ai_proposals/services/proposal_events_service.dart';
import '../../features/auth/domain/entities/auth_user.dart';
import '../../features/auth/domain/services/account_migration_service.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/health_sync/data/services/health_backend_sync_service.dart';
import '../../features/workout_logging/data/services/workout_sync_service.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../../features/workout_templates/data/services/template_sync_service.dart';
import '../di/service_locator.dart';
import '../demo/demo_mode.dart';
import '../navigation/app_router.dart' show navigatorKey;

/// Auth-driven side effects (account-data migration, sync start/stop, widget
/// refresh) extracted from the app widget. On login it migrates local data
/// safely (guest upgrade / account switch) BEFORE starting sync, then starts
/// background sync and refreshes home widgets; on a definitive sign-out it wipes
/// local data and stops sync.
class AuthSyncListeners extends StatelessWidget {
  const AuthSyncListeners({
    super.key,
    required this.child,
    this.challengeMode = kChallengeMode,
  });

  final Widget child;
  final bool challengeMode;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (prev, curr) => curr is AuthAuthenticated,
          listener: (context, state) {
            if (state is AuthAuthenticated) {
              final generation = _closeWebMcpForTransition();
              unawaited(_onAuthenticated(state.user, generation));
            }
          },
        ),
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (prev, curr) => curr is! AuthAuthenticated,
          listener: (context, state) {
            final generation = _closeWebMcpForTransition();
            _onUnauthenticated();
            if (state is AuthUnauthenticated) {
              unawaited(_openWebMcpForSettledGuest(generation));
            }
          },
        ),
      ],
      child: child,
    );
  }

  Future<void> _onAuthenticated(AuthUser user, int? gateGeneration) async {
    // Migrate local data BEFORE any sync runs so the cursor reset (guest upgrade)
    // or local wipe (account switch) takes effect before push/pull. Best-effort:
    // never throws into the auth flow.
    AccountMigration migration = AccountMigration.none;
    var migrationSucceeded = true;
    if (getIt.isRegistered<AccountMigrationService>()) {
      try {
        migration = await getIt<AccountMigrationService>().onAuthenticated(
          user,
        );
      } catch (e, st) {
        migrationSucceeded = false;
        dev.log('Account migration (login) failed', error: e, stackTrace: st);
      }
    }
    if (migration == AccountMigration.failed) migrationSucceeded = false;
    // Product reads stay closed if migration fails: local data may still belong
    // to the previous account. Do not start any account-scoped sync under the
    // newly authenticated token until a later transition isolates local data.
    if (!migrationSucceeded) return;
    _openWebMcpIfCurrent(gateGeneration);
    // The evaluator is fully in-memory. Keep WebMCP usable after the demo
    // account settles, but do not start token-backed sync, polling, widgets, or
    // health upload work that could escape the credential-free boundary.
    if (challengeMode) return;
    // Only a real link event (guest upgrade / account switch) value-times the
    // post-link confirmation — never a same-account cold-start rehydrate.
    final confirmBackup =
        migration == AccountMigration.guestUpgrade ||
        migration == AccountMigration.accountSwitch;

    try {
      final workoutWidget = getIt.isRegistered<WorkoutWidgetService>()
          ? getIt<WorkoutWidgetService>()
          : null;
      final nutritionWidget = getIt.isRegistered<NutritionWidgetService>()
          ? getIt<NutritionWidgetService>()
          : null;

      if (getIt.isRegistered<WorkoutSyncService>()) {
        final svc = getIt<WorkoutSyncService>();
        unawaited(
          _runFirstBackup(
            svc,
            workoutWidget,
            nutritionWidget,
            confirm: confirmBackup,
          ),
        );
        final prefs = getIt<PreferencesService>();
        if (await prefs.getBackgroundSyncEnabled()) {
          svc.startAutoSync();
        }
      } else if (nutritionWidget != null) {
        unawaited(nutritionWidget.updateNutritionSummaryWidget());
      }

      if (getIt.isRegistered<TemplateSyncService>()) {
        final tsvc = getIt<TemplateSyncService>();
        unawaited(() async {
          try {
            await tsvc.syncNow();
          } catch (e, st) {
            dev.log(
              'Post-login template sync failed',
              error: e,
              stackTrace: st,
            );
          }
        }());
        final prefs = getIt<PreferencesService>();
        if (await prefs.getBackgroundSyncEnabled()) {
          tsvc.startAutoSync();
        }
      }

      // A launch while signed out makes the bootstrap health sync a no-op.
      // Trigger an authenticated pass explicitly so OAuth completion does not
      // depend on another lifecycle transition to upload fresh HealthKit data.
      if (getIt.isRegistered<HealthBackendSyncService>()) {
        final healthSync = getIt<HealthBackendSyncService>();
        if (migration == AccountMigration.guestUpgrade ||
            migration == AccountMigration.accountSwitch) {
          healthSync.resetSyncEligibility();
        }
        healthSync.scheduleAuthenticatedSync();
      }

      // (Re)start the pending-proposal poller so the badge is live after a
      // sign-out/sign-in cycle (it was stopped on sign-out). start() is
      // idempotent, so the launch-path start in the bootstrapper still no-ops.
      if (getIt.isRegistered<ProposalCountService>()) {
        getIt<ProposalCountService>().start();
      }
    } catch (e, st) {
      dev.log('Auto-sync start failed', error: e, stackTrace: st);
    }
  }

  int? _closeWebMcpForTransition() {
    if (getIt.isRegistered<WebMcpAccessGate>()) {
      return getIt<WebMcpAccessGate>().closeForTransition();
    }
    return null;
  }

  void _openWebMcpIfCurrent(int? generation) {
    if (generation != null && getIt.isRegistered<WebMcpAccessGate>()) {
      getIt<WebMcpAccessGate>().openIfCurrent(generation);
    }
  }

  Future<void> _openWebMcpForSettledGuest(int? generation) async {
    if (generation == null || !getIt.isRegistered<PreferencesService>()) {
      return;
    }
    try {
      // An unauthenticated shell can also mean a recoverable refresh outage.
      // Keep account-scoped reads closed while a real account id remains linked;
      // explicit sign-out clears it before AuthUnauthenticated is emitted.
      if (await getIt<PreferencesService>().getAuthLastUserId() == null) {
        _openWebMcpIfCurrent(generation);
      }
    } catch (e, st) {
      dev.log('WebMCP guest access check failed', error: e, stackTrace: st);
    }
  }

  /// Runs the first post-login workout backup and, when [confirm] is set (a
  /// real guest-upgrade / account-switch link event), tells the user whether
  /// the "back up your workouts" promise was kept — success confirmation, or a
  /// warning with a Retry instead of a silent log.
  Future<void> _runFirstBackup(
    WorkoutSyncService svc,
    WorkoutWidgetService? workoutWidget,
    NutritionWidgetService? nutritionWidget, {
    required bool confirm,
  }) async {
    try {
      await svc.syncNow();
      await workoutWidget?.updateWorkoutsPerWeekWidget();
      if (confirm) {
        await _showBackedUpConfirmation();
      }
    } catch (e, st) {
      dev.log('Post-login workout sync failed', error: e, stackTrace: st);
      if (confirm) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          HustlSnack.show(
            ctx,
            "Couldn't back up your workouts. We'll keep trying.",
            variant: HustlSnackVariant.warning,
            actionLabel: 'Retry',
            onAction: () => unawaited(
              _runFirstBackup(
                svc,
                workoutWidget,
                nutritionWidget,
                confirm: true,
              ),
            ),
          );
        }
      }
    }

    try {
      await nutritionWidget?.updateNutritionSummaryWidget();
    } catch (e, st) {
      dev.log(
        'Post-login nutrition widget refresh failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Brief "Backed up — your N workouts are safe" confirmation surfaced after the
  /// post-login sync completes, only on a guest→account upgrade / account switch.
  /// Reuses the app-wide [HustlSnack] via the global navigator context; the count
  /// reflects the now-merged local store (so the user sees their real total).
  Future<void> _showBackedUpConfirmation() async {
    try {
      int count = 0;
      if (getIt.isRegistered<WorkoutRepository>()) {
        final sessions = await getIt<WorkoutRepository>().getWorkoutSessions();
        count = sessions.where((s) => s.isCompleted).length;
      }
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final message = count <= 0
          ? 'Backed up — your training is safe.'
          : count == 1
          ? 'Backed up — your 1 workout is safe.'
          : 'Backed up — your $count workouts are safe.';
      HustlSnack.show(ctx, message, variant: HustlSnackVariant.success);
    } catch (e, st) {
      dev.log('Post-link confirmation failed', error: e, stackTrace: st);
    }
  }

  void _onUnauthenticated() {
    try {
      if (getIt.isRegistered<WorkoutSyncService>()) {
        getIt<WorkoutSyncService>().stopAutoSync();
      }
      if (getIt.isRegistered<TemplateSyncService>()) {
        getIt<TemplateSyncService>().stopAutoSync();
      }
      // Stop polling and clear the badge immediately so the prior account's
      // pending count can't linger until the next poll after sign-out.
      if (getIt.isRegistered<ProposalCountService>()) {
        getIt<ProposalCountService>().stop();
      }
      if (getIt.isRegistered<ProposalEventsService>()) {
        getIt<ProposalEventsService>().setCount(0);
      }
    } catch (e, st) {
      dev.log('Auto-sync stop failed', error: e, stackTrace: st);
    }

    // NOTE: the destructive local-data wipe is intentionally NOT here. A generic
    // AuthUnauthenticated also fires on a transient auth-check/refresh failure
    // (getCurrentUser() returns null on a temporary network/5xx outage), so
    // wiping here would delete a returning user's local workouts during an
    // outage. The wipe now runs ONLY on the explicit sign-out path
    // (AuthBloc.onExplicitSignOut → AccountMigrationService.onUnauthenticated),
    // wired in service_locator.dart. The account-switch branch in
    // AccountMigrationService.onAuthenticated remains the primary cross-account
    // guard, so a different account signing in still wipes the prior account.
  }
}
