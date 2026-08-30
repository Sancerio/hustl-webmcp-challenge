import 'dart:convert';
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/domain/entities/auth_user.dart';

class PreferencesService {
  /// Live weekly-workout-goal value (1–14, default 3). Seeded on [init] and
  /// updated on every [setWeeklyWorkoutGoal] write so screens kept alive across
  /// tab switches — e.g. the Train hero ring — react to a goal change made on
  /// another tab (the Progress screen) without re-reading prefs.
  final ValueNotifier<int> weeklyWorkoutGoalListenable = ValueNotifier<int>(3);

  /// Live "show workouts from other apps in your day" value (default ON).
  /// Seeded from storage on [init] and updated on every
  /// [setShowExternalWorkoutsInDay] write — the single source of truth behind
  /// both [showExternalWorkoutsInDay] reads — so an already-mounted dashboard
  /// (the day's-ledger receipt) reacts to a Settings flip without waiting for
  /// an incidental rebuild.
  final ValueNotifier<bool> _showExternalWorkoutsInDay = ValueNotifier<bool>(
    true,
  );

  /// Observable view of [showExternalWorkoutsInDay] for surfaces that must
  /// react to a Settings flip while already mounted.
  ValueListenable<bool> get showExternalWorkoutsInDayListenable =>
      _showExternalWorkoutsInDay;

  // Onboarding v3 intro (branded carousel + welcome; gated by HUSTL_ONBOARDING_V3)
  static const String _keyOnboardingIntroSeen = 'onboarding_intro_seen';
  // Onboarding v3 first-win "Building your plan" summary (shown once, after the
  // user's first completed workout).
  static const String _keyOnboardingFirstWinSeen = 'onboarding_first_win_seen';
  // Onboarding v3 "AI magic moment": the user's one-time consent for the coach
  // to draft a starter proposal from their own logs, and the once-only "seen"
  // flag that gates the magic moment so it never re-prompts.
  static const String _keyOnboardingProposalConsent =
      'onboarding_proposal_consent';
  static const String _keyOnboardingProposalSeen = 'onboarding_proposal_seen';
  // Lifetime count of AI proposals the user has approved. Incremented by the
  // ProposalsBloc on each successful approve; feeds the coach-readiness loop.
  static const String _keyApprovedProposalsCount = 'approved_proposals_count';
  // Watermark (applied_at) of the newest AUTO-applied AI log the app has already
  // surfaced a notification for, so each is notified at most once.
  static const String _keyAiAutoLogLastSeen = 'ai_auto_log_last_seen_at';

  // Onboarding v2
  static const String _keyOnboardingV2SeenEntry = 'onboarding_v2_seen_entry';
  static const String _keyOnboardingV2SeenCoachmarkStartWorkout =
      'onboarding_v2_seen_coachmark_start_workout';
  static const String _keyOnboardingV2SeenCoachmarkLogFirstSet =
      'onboarding_v2_seen_coachmark_log_first_set';
  static const String _keyOnboardingV2SeenFirstWin =
      'onboarding_v2_seen_first_win';
  static const String _keyOnboardingV2SeenSigninNudge =
      'onboarding_v2_seen_signin_nudge';
  static const String _keyOnboardingV2SeenNotificationPrimer =
      'onboarding_v2_seen_notification_primer';
  static const String _keyAutoStartRestTimer = 'auto_start_rest_timer';
  static const String _keySupersetAutoAdvance = 'superset_auto_advance';
  static const String _keySeenSupersetHint = 'seen_superset_hint';
  static const String _keyCoachIntroSeen = 'coach_intro_seen';
  static const String _keySeenMealScanCameraPrimer =
      'seen_meal_scan_camera_primer';
  // Value-timed Apple Health connect primer, shown once before the first
  // weight-log (never at launch). Gated so it shows exactly once and never
  // dead-ends — declining proceeds to the manual weight entry.
  static const String _keySeenHealthConnectPrimer =
      'seen_health_connect_primer';
  static const String _keyFavoriteExercises = 'favorite_exercises';
  static const String _keyDismissedSyncBanner = 'dismissed_sync_banner';
  static const String _keyAuthUser = 'auth_user';
  // The id of the last REAL (non-guest) account that authenticated on this
  // device. Lets [AccountMigrationService] tell a guest→account upgrade (absent)
  // apart from an account switch (different id) on login.
  static const String _keyAuthLastUserId = 'auth_last_user_id';
  static const String _keyWeeklyWorkoutGoal = 'weekly_workout_goal';
  static const String _keyWeightUnit = 'weight_unit'; // 'kg' | 'lb'
  static const String _keySuggestNextSetTargets = 'suggest_next_set_targets';
  static const String _keyWeeklyTrainingRecapEnabled =
      'weekly_training_recap_enabled';
  static const String _keyHasWebSession = 'auth_has_web_session';
  static const String _keyExerciseRestTimers = 'exercise_rest_timers';
  static const String _keyThemeMode =
      'theme_mode'; // 'system' | 'light' | 'dark'
  static const String _keyWorkoutsSyncVersion = 'sync_workouts_version';
  static const String _keyWorkoutsLastSyncAt = 'sync_workouts_last_at';
  static const String _keyWorkoutsUploadOffset = 'sync_workouts_upload_offset';
  static const String _keyWorkoutsUploadSignature = 'sync_workouts_upload_sig';
  static const String _keyWorkoutsDeletedIds = 'sync_workouts_deleted_ids';
  // Templates sync keys
  static const String _keyTemplatesSyncVersion = 'sync_templates_version';
  static const String _keyTemplatesLastSyncAt = 'sync_templates_last_at';
  static const String _keyTemplatesUploadOffset =
      'sync_templates_upload_offset';
  static const String _keyTemplatesUploadSignature =
      'sync_templates_upload_sig';
  static const String _keyTemplatesDeletedIds = 'sync_templates_deleted_ids';
  static const String _keyTemplatesDirtyIds = 'sync_templates_dirty_ids';
  static const String _keyTemplatesVersionById = 'sync_templates_version_by_id';
  static const String _keyHealthPermissionsDenied = 'health_permissions_denied';
  // Count of consecutive health-permission request attempts that did not result
  // in any granted type. Used to distinguish a transient first cancel/dismiss
  // from a confirmed re-denial: we only mark permanently-denied once this
  // crosses the confirmed-re-denial threshold. Reset to 0 on any successful
  // (connected) request.
  static const String _keyHealthPermissionRequestCount =
      'health_permission_request_count';
  static const String _keyWorkoutWritebackMappings =
      'workout_writeback_mappings_v1';
  static const String _keyWorkoutWritebackEnabledIos =
      'workout_writeback_enabled_ios';
  static const String _keyWorkoutWritebackEnabledAndroid =
      'workout_writeback_enabled_android';
  static const String _keyPrFlagsRecomputedV1 = 'pr_flags_recomputed_v1';
  static const String _keyNutritionWeighInPromptDismissedDay =
      'nutrition_weigh_in_prompt_dismissed_day';
  static const String _keyWatchCompanionEnabled = 'watch_companion_enabled';
  static const String _keyWatchCompanionDebugOverride =
      'watch_companion_debug_override';
  static const String _keyWatchHeartRateRecordingEnabled =
      'watch_heart_rate_recording_enabled';
  static const String _keyAiCaptureConsent = 'ai_capture_consent';
  // Weekly nutrition check-in reminder (local notification).
  static const String _keyNutritionCheckInReminderEnabled =
      'nutrition_checkin_reminder_enabled';
  static const String _keyNutritionCheckInReminderWeekday =
      'nutrition_checkin_reminder_weekday';
  static const String _keyNutritionCheckInReminderHour =
      'nutrition_checkin_reminder_hour';
  static const String _keyNutritionCheckInReminderMinute =
      'nutrition_checkin_reminder_minute';
  // One-time rationale before the OS notification prompt on the Strategy screen.
  static const String _keySeenNutritionNotificationPrimer =
      'seen_nutrition_notification_primer';
  // Behavioral-momentum coach tips (adaptive-coach item 4). Opt-in, default off:
  // the coach only responds to multi-week streaks/slips when explicitly enabled.
  static const String _keyBehavioralMomentumOptIn =
      'behavioral_momentum_opt_in';
  // Coach Explains narrative (adaptive-coach item 6). Opt-in, default off and
  // INDEPENDENT of momentum: only when enabled does the Insights screen lazily
  // fetch the LLM note. The server flag is also off by default, so this stays
  // a no-op even when on until the backend feature is deliberately enabled.
  static const String _keyCoachExplainsOptIn = 'coach_explains_opt_in';

  // Whether the "day's ledger" strain receipt itemizes workouts imported from
  // other apps (plan 012). Default ON: the receipt is more honest when it shows
  // every session that drove today's strain. When OFF, external rows are hidden
  // and their share is re-absorbed into ambient movement.
  static const String _keyShowExternalWorkoutsInDay =
      'show_external_workouts_in_day';

  static const String _keyBackgroundSyncEnabled = 'background_sync_enabled';
  static const String _keyHapticsEnabled = 'haptics_enabled';
  static const String _keyDebugMode = 'debug_mode';
  static const String _keyInactivityReminderMinutes =
      'inactivity_reminder_minutes';
  // Exercise list view mode
  static const String _keyExerciseListCompact = 'exercise_list_compact';
  // Add-food flow: false = speed (stay in search after a stage), true = context
  // (auto-open the plate review after each stage).
  static const String _keyAddFoodContextMode = 'add_food_context_mode';
  // Record tab preferences
  static const String _keyRecordTabGroup = 'record_tab_group'; // int enum index
  static const String _keyRecordTabUse1Rm = 'record_tab_use_1rm'; // bool
  static const String _keyRecordTabQuickRange =
      'record_tab_quick_range'; // int enum index or absent
  // Health backend-sync high-watermark: the last calendar day (YYYY-MM-DD,
  // local) successfully uploaded per sync kind ('weight' | 'recovery'). Used to
  // avoid re-POSTing the full 30-day window on every cold start; only days newer
  // than (watermark - overlap) are read+uploaded. Absent on first run.
  static const String _keyHealthSyncWatermarkPrefix = 'health_sync_watermark_';

  // ------- Telemetry (privacy-safe onboarding funnel analytics) -------
  // Runtime opt-out for ALL client telemetry. Default false (telemetry on).
  static const String _keyTelemetryOptOut = 'telemetry_opt_out';
  // A random per-install seed minted once and stored locally. Only its opaque
  // SHA-256 hash is ever emitted — never the raw seed, never a device id.
  static const String _keyTelemetryInstallId = 'telemetry_install_id';

  static final PreferencesService _instance = PreferencesService._internal();
  SharedPreferences? _prefs;

  factory PreferencesService() {
    return _instance;
  }

  PreferencesService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    weeklyWorkoutGoalListenable.value =
        _prefs?.getInt(_keyWeeklyWorkoutGoal) ?? 3;
    _showExternalWorkoutsInDay.value =
        _prefs?.getBool(_keyShowExternalWorkoutsInDay) ?? true;
  }

  @visibleForTesting
  void resetForTests() {
    _prefs = null;
    // This is a singleton, so reset notifier-backed state too — otherwise its
    // value leaks across tests and makes order-dependent suites flaky.
    weeklyWorkoutGoalListenable.value = 3;
    _showExternalWorkoutsInDay.value = true;
  }

  Map<String, T> _getMap<T>(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final Map<String, T> typed = {};
      decoded.forEach((k, v) {
        if (v is T) typed[k] = v;
      });
      return typed;
    } catch (_) {
      return {};
    }
  }

  Future<void> _setMap(String key, Map<String, dynamic> value) async {
    await _prefs?.setString(key, json.encode(value));
  }

  Future<String?> getRawString(String key) async {
    if (_prefs == null) await init();
    return _prefs?.getString(key);
  }

  Future<void> setRawString(String key, String? value) async {
    if (_prefs == null) await init();
    if (value == null) {
      await _prefs?.remove(key);
    } else {
      await _prefs?.setString(key, value);
    }
  }

  Future<String?> getNutritionWeighInPromptDismissedDay() async {
    if (_prefs == null) await init();
    return _prefs?.getString(_keyNutritionWeighInPromptDismissedDay);
  }

  Future<void> setNutritionWeighInPromptDismissedDay(String? value) async {
    if (_prefs == null) await init();
    if (value == null) {
      await _prefs?.remove(_keyNutritionWeighInPromptDismissedDay);
    } else {
      await _prefs?.setString(_keyNutritionWeighInPromptDismissedDay, value);
    }
  }

  Future<bool> getWatchCompanionEnabled() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyWatchCompanionEnabled) ?? false;
  }

  Future<bool?> getWatchCompanionEnabledOrNull() async {
    if (_prefs == null) await init();
    final prefs = _prefs;
    if (prefs == null) return null;
    if (!prefs.containsKey(_keyWatchCompanionEnabled)) return null;
    return prefs.getBool(_keyWatchCompanionEnabled);
  }

  Future<void> setWatchCompanionEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyWatchCompanionEnabled, value);
  }

  Future<bool> getWatchHeartRateRecordingEnabled() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyWatchHeartRateRecordingEnabled) ?? true;
  }

  Future<void> setWatchHeartRateRecordingEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyWatchHeartRateRecordingEnabled, value);
  }

  Future<bool?> getWatchCompanionDebugOverride() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyWatchCompanionDebugOverride);
  }

  Future<void> setWatchCompanionDebugOverride(bool? value) async {
    if (_prefs == null) await init();
    if (value == null) {
      await _prefs?.remove(_keyWatchCompanionDebugOverride);
      return;
    }
    await _prefs?.setBool(_keyWatchCompanionDebugOverride, value);
  }

  // ------- Onboarding v3 intro (branded carousel + welcome) -------
  /// Whether the first-run branded intro has been seen/completed. Synchronous so
  /// the GoRouter redirect can read it at route-resolution time (`_prefs` is
  /// populated by the awaited `init()` during DI, before the first frame).
  bool get onboardingIntroSeen =>
      _prefs?.getBool(_keyOnboardingIntroSeen) ?? false;

  Future<void> setOnboardingIntroSeen(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingIntroSeen, value);
  }

  /// Whether the first-win "Building your plan" summary has been shown. Synchronous
  /// so the active-workout trigger can gate on it without awaiting (mirrors
  /// [onboardingIntroSeen]).
  bool get onboardingFirstWinSeen =>
      _prefs?.getBool(_keyOnboardingFirstWinSeen) ?? false;

  Future<void> setOnboardingFirstWinSeen(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingFirstWinSeen, value);
  }

  // ------- Onboarding v3 "AI magic moment" (starter proposal) -------
  /// Whether the user has consented to the coach drafting a starter proposal
  /// from their own logs. Default false; required BEFORE generating a draft.
  /// This is a first-party draft from the user's own data — there is no external
  /// grant to revoke; the toggle simply gates whether we draft at all.
  bool get onboardingProposalConsent =>
      _prefs?.getBool(_keyOnboardingProposalConsent) ?? false;

  Future<void> setOnboardingProposalConsent(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingProposalConsent, value);
  }

  /// Whether the magic-moment screen has already been shown/dismissed. Sync so
  /// the eligibility gate can read it without awaiting (mirrors
  /// [onboardingIntroSeen]); set once the user reaches or leaves the screen so
  /// it never re-prompts.
  bool get onboardingProposalSeen =>
      _prefs?.getBool(_keyOnboardingProposalSeen) ?? false;

  Future<void> setOnboardingProposalSeen(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingProposalSeen, value);
  }

  /// Lifetime count of approved AI proposals. Sync getter (mirrors the other
  /// readiness-input getters); incremented by [incrementApprovedProposalsCount].
  int get approvedProposalsCount =>
      _prefs?.getInt(_keyApprovedProposalsCount) ?? 0;

  /// Bump the approved-proposals counter by one (called on approve success).
  Future<void> incrementApprovedProposalsCount() async {
    if (_prefs == null) await init();
    final next = (_prefs?.getInt(_keyApprovedProposalsCount) ?? 0) + 1;
    await _prefs?.setInt(_keyApprovedProposalsCount, next);
  }

  // ------- Onboarding v2 -------
  /// Sync read of the v2 entry flag — the onboarding redirect uses it to treat
  /// already-onboarded users as having seen onboarding (so enabling the v3 flag
  /// never re-onboards an existing user).
  bool get onboardingV2SeenEntrySync =>
      _prefs?.getBool(_keyOnboardingV2SeenEntry) ?? false;

  /// Sync "this is a returning (non-guest) user" signal for the onboarding gate.
  /// Note: the persisted auth user is only written on web today, so on native
  /// this term collapses to the v2-entry flag; the awaited startup migration in
  /// `service_locator.dart` adds the native web-session / completed-history
  /// signal so existing users are never re-onboarded.
  bool get hasReturningUserSignal {
    if (onboardingV2SeenEntrySync) return true;
    final raw = getAuthUserJson();
    if (raw == null || raw.isEmpty) return false;
    try {
      return !AuthUser.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      ).isGuest;
    } catch (_) {
      return false;
    }
  }

  Future<bool> getOnboardingV2SeenEntry() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyOnboardingV2SeenEntry) ?? false;
  }

  Future<void> setOnboardingV2SeenEntry(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingV2SeenEntry, value);
  }

  // ------- AI meal capture consent (one-time) -------
  Future<bool> getAiCaptureConsent() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyAiCaptureConsent) ?? false;
  }

  Future<void> setAiCaptureConsent(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyAiCaptureConsent, value);
  }

  // ------- Weekly nutrition check-in reminder -------
  /// Whether the opt-in weekly check-in reminder is armed. Default false — the
  /// nudge only exists once the user explicitly turns it on (primer or Settings).
  Future<bool> getNutritionCheckInReminderEnabled() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyNutritionCheckInReminderEnabled) ?? false;
  }

  Future<void> setNutritionCheckInReminderEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyNutritionCheckInReminderEnabled, value);
  }

  /// Reminder weekday (DateTime.monday = 1 … sunday = 7), default Monday.
  Future<int> getNutritionCheckInReminderWeekday() async {
    if (_prefs == null) await init();
    final raw =
        _prefs?.getInt(_keyNutritionCheckInReminderWeekday) ?? DateTime.monday;
    return raw.clamp(DateTime.monday, DateTime.sunday);
  }

  Future<void> setNutritionCheckInReminderWeekday(int weekday) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(
      _keyNutritionCheckInReminderWeekday,
      weekday.clamp(DateTime.monday, DateTime.sunday),
    );
  }

  /// Reminder hour (0–23), default 9am.
  Future<int> getNutritionCheckInReminderHour() async {
    if (_prefs == null) await init();
    return (_prefs?.getInt(_keyNutritionCheckInReminderHour) ?? 9).clamp(0, 23);
  }

  /// Reminder minute (0–59), default 0.
  Future<int> getNutritionCheckInReminderMinute() async {
    if (_prefs == null) await init();
    return (_prefs?.getInt(_keyNutritionCheckInReminderMinute) ?? 0).clamp(
      0,
      59,
    );
  }

  Future<void> setNutritionCheckInReminderTime(int hour, int minute) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyNutritionCheckInReminderHour, hour.clamp(0, 23));
    await _prefs?.setInt(
      _keyNutritionCheckInReminderMinute,
      minute.clamp(0, 59),
    );
  }

  /// True once the Strategy-screen notification rationale has been shown, so it
  /// never re-appears regardless of the user's choice.
  Future<bool> getSeenNutritionNotificationPrimer() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keySeenNutritionNotificationPrimer) ?? false;
  }

  Future<void> setSeenNutritionNotificationPrimer(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keySeenNutritionNotificationPrimer, value);
  }

  // ------- Behavioral-momentum coach tips (opt-in) -------
  /// Whether the multi-week behavioral-momentum coach tips are enabled. Default
  /// false — these respond to streaks/slips and only appear once the user opts
  /// in, so the Insights coach is never noisy by default.
  Future<bool> getBehavioralMomentumEnabled() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyBehavioralMomentumOptIn) ?? false;
  }

  Future<void> setBehavioralMomentumEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyBehavioralMomentumOptIn, value);
  }

  // ------- Coach Explains narrative (opt-in, item 6) -------
  /// Whether the optional LLM "Coach Explains" narrative is enabled. Default
  /// false — and independent of momentum. Even when on it is a no-op unless the
  /// backend feature flag is also enabled (off by default).
  Future<bool> getCoachExplainsEnabled() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyCoachExplainsOptIn) ?? false;
  }

  Future<void> setCoachExplainsEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyCoachExplainsOptIn, value);
  }

  /// Whether the day's-ledger strain receipt itemizes workouts imported from
  /// other apps. Defaults to true.
  Future<bool> getShowExternalWorkoutsInDay() async {
    if (_prefs == null) await init();
    return _showExternalWorkoutsInDay.value;
  }

  /// Synchronous read of [getShowExternalWorkoutsInDay] so an already-mounted
  /// dashboard can cheaply read the current value during build; pair with
  /// [showExternalWorkoutsInDayListenable] to be TOLD when it changes.
  bool get showExternalWorkoutsInDay => _showExternalWorkoutsInDay.value;

  Future<void> setShowExternalWorkoutsInDay(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyShowExternalWorkoutsInDay, value);
    _showExternalWorkoutsInDay.value = value;
  }

  Future<bool> getOnboardingV2SeenCoachmarkStartWorkout() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyOnboardingV2SeenCoachmarkStartWorkout) ?? false;
  }

  Future<void> setOnboardingV2SeenCoachmarkStartWorkout(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingV2SeenCoachmarkStartWorkout, value);
  }

  /// True once the celebratory first-workout-logged sheet has been shown.
  Future<bool> getOnboardingV2SeenFirstWin() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyOnboardingV2SeenFirstWin) ?? false;
  }

  Future<void> setOnboardingV2SeenFirstWin(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingV2SeenFirstWin, value);
  }

  /// True once the guest "back up your progress" sign-in nudge has been shown.
  Future<bool> getOnboardingV2SeenSigninNudge() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyOnboardingV2SeenSigninNudge) ?? false;
  }

  Future<void> setOnboardingV2SeenSigninNudge(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingV2SeenSigninNudge, value);
  }

  /// True once we've shown the in-context notification permission primer, so
  /// we never re-prompt regardless of the user's choice.
  Future<bool> getOnboardingV2SeenNotificationPrimer() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyOnboardingV2SeenNotificationPrimer) ?? false;
  }

  Future<void> setOnboardingV2SeenNotificationPrimer(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingV2SeenNotificationPrimer, value);
  }

  Future<bool> getOnboardingV2SeenCoachmarkLogFirstSet() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyOnboardingV2SeenCoachmarkLogFirstSet) ?? false;
  }

  Future<void> setOnboardingV2SeenCoachmarkLogFirstSet(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyOnboardingV2SeenCoachmarkLogFirstSet, value);
  }

  // Get whether to auto-start rest timer after completing a set (default: true)
  bool get shouldAutoStartRestTimer =>
      _prefs?.getBool(_keyAutoStartRestTimer) ?? true;

  // Set whether to auto-start rest timer
  Future<void> setAutoStartRestTimer(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyAutoStartRestTimer, value);
  }

  // ------- Superset auto-advance -------
  // Whether completing a set in a grouped exercise auto-advances to the next
  // group member's matching-round set. Default: true (on by default).
  Future<bool> getSupersetAutoAdvance() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keySupersetAutoAdvance) ?? true;
  }

  Future<void> setSupersetAutoAdvance(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keySupersetAutoAdvance, value);
  }

  // Whether the one-time "group exercises into a superset" hint has been shown.
  Future<bool> getSeenSupersetHint() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keySeenSupersetHint) ?? false;
  }

  Future<void> setSeenSupersetHint(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keySeenSupersetHint, value);
  }

  // ------- Coach intro (one-time "meet your Coach" explainer) -------
  /// True once the one-time "meet your Coach" intro has been shown.
  Future<bool> getCoachIntroSeen() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyCoachIntroSeen) ?? false;
  }

  Future<void> setCoachIntroSeen(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyCoachIntroSeen, value);
  }

  // ------- Meal-scan camera primer (one-time rationale) -------
  /// True once the in-context "we'll need camera access" rationale has been
  /// shown before a meal scan, so it never re-appears on later scans.
  Future<bool> getSeenMealScanCameraPrimer() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keySeenMealScanCameraPrimer) ?? false;
  }

  Future<void> setSeenMealScanCameraPrimer(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keySeenMealScanCameraPrimer, value);
  }

  // ------- Health-connect primer (value-timed, one-time before first weight-log) -------
  /// True once the value-timed Apple Health connect primer has been shown before
  /// the first weight-log, so it never re-appears regardless of the user's
  /// choice. Synchronous so the weight-log entry can gate without awaiting
  /// (mirrors [onboardingIntroSeen]); `_prefs` is populated by the awaited
  /// `init()` during DI, before the first frame.
  bool get seenHealthConnectPrimer =>
      _prefs?.getBool(_keySeenHealthConnectPrimer) ?? false;

  Future<void> setSeenHealthConnectPrimer(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keySeenHealthConnectPrimer, value);
  }

  // ------- Exercise rest timers -------
  Future<int?> getExerciseRestTimer(String exerciseName) async {
    if (_prefs == null) await init();
    final map = _getMap<int>(_keyExerciseRestTimers);
    final value = map[exerciseName];
    return (value?.clamp(1, 600))?.toInt();
  }

  Future<void> setExerciseRestTimer(String exerciseName, int? seconds) async {
    if (_prefs == null) await init();
    final map = _getMap<int>(_keyExerciseRestTimers);
    if (seconds == null) {
      map.remove(exerciseName);
    } else {
      map[exerciseName] = seconds.clamp(1, 600);
    }
    await _setMap(_keyExerciseRestTimers, map);
  }

  // ------- Exercise favorites -------
  // Return the set of favorited exercise names
  Set<String> getFavoriteExercises() {
    final list = _prefs?.getStringList(_keyFavoriteExercises) ?? <String>[];
    return list.toSet();
  }

  // Check if an exercise is favorited
  bool isExerciseFavorite(String exerciseName) {
    return getFavoriteExercises().contains(exerciseName);
  }

  // Toggle favorite state for an exercise
  Future<bool> toggleFavoriteExercise(String exerciseName) async {
    if (_prefs == null) await init();
    final favorites = getFavoriteExercises();
    final wasFavorite = favorites.contains(exerciseName);
    if (wasFavorite) {
      favorites.remove(exerciseName);
    } else {
      favorites.add(exerciseName);
    }
    await _prefs?.setStringList(_keyFavoriteExercises, favorites.toList());
    return !wasFavorite;
  }

  // ------- Auth user persistence -------
  String? getAuthUserJson() {
    return _prefs?.getString(_keyAuthUser);
  }

  Future<void> setAuthUserJson(String? json) async {
    if (_prefs == null) await init();
    if (json == null) {
      await _prefs?.remove(_keyAuthUser);
    } else {
      await _prefs?.setString(_keyAuthUser, json);
    }
  }

  Future<void> clearAuthUser() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyAuthUser);
  }

  // ------- Last linked real-account id (guest-upgrade / account-switch guard) -------
  /// The id of the last REAL account (non-guest) that authenticated on this
  /// device, or null if only a guest has ever used the app. Read by
  /// [AccountMigrationService] to distinguish a guest→account upgrade (null)
  /// from an account switch (a different id) on login.
  Future<String?> getAuthLastUserId() async {
    if (_prefs == null) await init();
    return _prefs?.getString(_keyAuthLastUserId);
  }

  Future<void> setAuthLastUserId(String id) async {
    if (_prefs == null) await init();
    await _prefs?.setString(_keyAuthLastUserId, id);
  }

  Future<void> clearAuthLastUserId() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyAuthLastUserId);
  }

  // ------- Web auth session hint (cookie-based refresh exists) -------
  Future<bool> getHasWebSession() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyHasWebSession) ?? false;
  }

  Future<void> setHasWebSession(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyHasWebSession, value);
  }

  // ------- UI banners -------
  Future<bool> isSyncBannerDismissed() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyDismissedSyncBanner) ?? false;
  }

  Future<void> dismissSyncBanner() async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyDismissedSyncBanner, true);
  }

  // ------- Weekly workout goal -------
  Future<int> getWeeklyWorkoutGoal() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyWeeklyWorkoutGoal) ?? 3; // default 3/wk
  }

  Future<void> setWeeklyWorkoutGoal(int goalPerWeek) async {
    if (_prefs == null) await init();
    final clamped = goalPerWeek.clamp(1, 14);
    await _prefs?.setInt(_keyWeeklyWorkoutGoal, clamped);
    weeklyWorkoutGoalListenable.value = clamped;
  }

  // ------- Weight unit ('kg' | 'lb', default inferred 'kg') -------
  Future<String> getWeightUnit() async {
    if (_prefs == null) await init();
    final raw = _prefs?.getString(_keyWeightUnit);
    return raw == 'lb' ? 'lb' : 'kg';
  }

  Future<void> setWeightUnit(String unit) async {
    if (_prefs == null) await init();
    await _prefs?.setString(_keyWeightUnit, unit == 'lb' ? 'lb' : 'kg');
  }

  // ------- Next-set target suggestions (progressive overload) -------
  /// Whether the set row shows a tap-to-accept next-set target (progressive
  /// overload) derived from the previous session. Default ON. Synchronous so the
  /// set row can read it at build time without awaiting (`_prefs` is populated by
  /// the awaited `init()` during DI, before the first frame).
  bool get suggestNextSetTargets =>
      _prefs?.getBool(_keySuggestNextSetTargets) ?? true;

  Future<void> setSuggestNextSetTargets(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keySuggestNextSetTargets, value);
  }

  // ------- Weekly training recap reminder -------
  /// Whether the opt-in weekly training recap reminder is armed. Default false —
  /// the nudge only exists once the user explicitly turns it on in Settings.
  /// Mirrors the nutrition check-in's opt-in shape (one gentle nudge a week).
  bool get weeklyTrainingRecapEnabled =>
      _prefs?.getBool(_keyWeeklyTrainingRecapEnabled) ?? false;

  /// Persist the [weeklyTrainingRecapEnabled] opt-in.
  Future<void> setWeeklyTrainingRecapEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyWeeklyTrainingRecapEnabled, value);
  }

  // ------- Theme mode -------
  Future<String> getRawThemeMode() async {
    if (_prefs == null) await init();
    return _prefs?.getString(_keyThemeMode) ?? 'system';
  }

  Future<void> setRawThemeMode(String mode) async {
    if (_prefs == null) await init();
    await _prefs?.setString(_keyThemeMode, mode);
  }

  // ------- Workout PR flags (legacy migration) -------
  Future<bool> getPrFlagsRecomputedV1() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyPrFlagsRecomputedV1) ?? false;
  }

  Future<void> setPrFlagsRecomputedV1(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyPrFlagsRecomputedV1, value);
  }

  // ------- Sync: workouts -------
  Future<int> getWorkoutsSyncVersion() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyWorkoutsSyncVersion) ?? 0;
  }

  Future<void> setWorkoutsSyncVersion(int v) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyWorkoutsSyncVersion, v);
  }

  Future<DateTime?> getAiAutoLogLastSeen() async {
    if (_prefs == null) await init();
    final ts = _prefs?.getInt(_keyAiAutoLogLastSeen);
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  Future<void> setAiAutoLogLastSeen(DateTime when) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyAiAutoLogLastSeen, when.millisecondsSinceEpoch);
  }

  Future<DateTime?> getWorkoutsLastSyncAt() async {
    if (_prefs == null) await init();
    final ts = _prefs?.getInt(_keyWorkoutsLastSyncAt);
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  Future<void> setWorkoutsLastSyncAt(DateTime when) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyWorkoutsLastSyncAt, when.millisecondsSinceEpoch);
  }

  // ------- Health backend-sync watermark -------
  /// The last calendar day (YYYY-MM-DD, local) successfully synced for [kind]
  /// ('weight' | 'recovery'), or null on first run.
  Future<String?> getHealthSyncWatermark(String kind) async {
    if (_prefs == null) await init();
    return _prefs?.getString('$_keyHealthSyncWatermarkPrefix$kind');
  }

  /// Record [day] (YYYY-MM-DD, local) as the latest day synced for [kind].
  Future<void> setHealthSyncWatermark(String kind, String day) async {
    if (_prefs == null) await init();
    await _prefs?.setString('$_keyHealthSyncWatermarkPrefix$kind', day);
  }

  // ------- Sync upload resume -------
  Future<int> getWorkoutsUploadOffset() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyWorkoutsUploadOffset) ?? 0;
  }

  Future<void> setWorkoutsUploadOffset(int offset) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyWorkoutsUploadOffset, offset.clamp(0, 1 << 30));
  }

  Future<String?> getWorkoutsUploadSignature() async {
    if (_prefs == null) await init();
    return _prefs?.getString(_keyWorkoutsUploadSignature);
  }

  Future<void> setWorkoutsUploadSignature(String? sig) async {
    if (_prefs == null) await init();
    if (sig == null || sig.isEmpty) {
      await _prefs?.remove(_keyWorkoutsUploadSignature);
    } else {
      await _prefs?.setString(_keyWorkoutsUploadSignature, sig);
    }
  }

  Future<void> clearWorkoutsUploadProgress() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyWorkoutsUploadOffset);
    await _prefs?.remove(_keyWorkoutsUploadSignature);
  }

  /// Reset the workout pull/push cursors so the NEXT sync re-pulls the account's
  /// full server history (and re-pushes local rows from the start). Keeps the
  /// local store + its deletion queue intact — used on a guest→account upgrade
  /// where the dirty guest rows must still upload (the merge).
  Future<void> resetWorkoutSyncCursors() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyWorkoutsSyncVersion);
    await _prefs?.remove(_keyWorkoutsLastSyncAt);
    await clearWorkoutsUploadProgress();
  }

  /// Clear ALL workout sync state (cursors + upload resume + queued deletions)
  /// for an account switch / sign-out, so the next account starts from a clean
  /// slate and never re-uploads the prior account's queued deletions.
  Future<void> clearWorkoutSyncState() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyWorkoutsSyncVersion);
    await _prefs?.remove(_keyWorkoutsLastSyncAt);
    await _prefs?.remove(_keyWorkoutsDeletedIds);
    await clearWorkoutsUploadProgress();
  }

  // ------- Sync deletions -------
  Future<List<String>> getWorkoutsDeletedIds() async {
    if (_prefs == null) await init();
    return _prefs?.getStringList(_keyWorkoutsDeletedIds) ?? <String>[];
  }

  // ------- Sync: templates -------
  Future<int> getTemplatesSyncVersion() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyTemplatesSyncVersion) ?? 0;
  }

  Future<void> setTemplatesSyncVersion(int v) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyTemplatesSyncVersion, v);
  }

  Future<DateTime?> getTemplatesLastSyncAt() async {
    if (_prefs == null) await init();
    final ts = _prefs?.getInt(_keyTemplatesLastSyncAt);
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  Future<void> setTemplatesLastSyncAt(DateTime when) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyTemplatesLastSyncAt, when.millisecondsSinceEpoch);
  }

  Future<List<String>> getTemplatesDirtyIds() async {
    if (_prefs == null) await init();
    return _prefs?.getStringList(_keyTemplatesDirtyIds) ?? <String>[];
  }

  Future<void> addTemplatesDirtyId(String id) async {
    if (_prefs == null) await init();
    final list = await getTemplatesDirtyIds();
    if (!list.contains(id)) {
      list.add(id);
      await _prefs?.setStringList(_keyTemplatesDirtyIds, list);
    }
  }

  Future<void> removeTemplatesDirtyIds(Iterable<String> ids) async {
    if (_prefs == null) await init();
    final list = await getTemplatesDirtyIds();
    list.removeWhere(ids.contains);
    if (list.isEmpty) {
      await _prefs?.remove(_keyTemplatesDirtyIds);
    } else {
      await _prefs?.setStringList(_keyTemplatesDirtyIds, list);
    }
  }

  Future<List<String>> getTemplatesDeletedIds() async {
    if (_prefs == null) await init();
    return _prefs?.getStringList(_keyTemplatesDeletedIds) ?? <String>[];
  }

  Future<void> addTemplatesDeletedId(String id) async {
    if (_prefs == null) await init();
    final list = await getTemplatesDeletedIds();
    if (!list.contains(id)) {
      list.add(id);
      await _prefs?.setStringList(_keyTemplatesDeletedIds, list);
    }
  }

  Future<void> removeTemplatesDeletedIds(Iterable<String> ids) async {
    if (_prefs == null) await init();
    final list = await getTemplatesDeletedIds();
    list.removeWhere(ids.contains);
    if (list.isEmpty) {
      await _prefs?.remove(_keyTemplatesDeletedIds);
    } else {
      await _prefs?.setStringList(_keyTemplatesDeletedIds, list);
    }
  }

  Future<void> addWorkoutsDeletedId(String id) async {
    if (_prefs == null) await init();
    final list = await getWorkoutsDeletedIds();
    if (!list.contains(id)) {
      list.add(id);
      await _prefs?.setStringList(_keyWorkoutsDeletedIds, list);
    }
  }

  Future<void> removeWorkoutsDeletedIds(Iterable<String> ids) async {
    if (_prefs == null) await init();
    final list = await getWorkoutsDeletedIds();
    list.removeWhere(ids.contains);
    if (list.isEmpty) {
      await _prefs?.remove(_keyWorkoutsDeletedIds);
    } else {
      await _prefs?.setStringList(_keyWorkoutsDeletedIds, list);
    }
  }

  Future<int> getTemplatesUploadOffset() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyTemplatesUploadOffset) ?? 0;
  }

  Future<void> setTemplatesUploadOffset(int offset) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyTemplatesUploadOffset, offset.clamp(0, 1 << 30));
  }

  Future<String?> getTemplatesUploadSignature() async {
    if (_prefs == null) await init();
    return _prefs?.getString(_keyTemplatesUploadSignature);
  }

  Future<void> setTemplatesUploadSignature(String? sig) async {
    if (_prefs == null) await init();
    if (sig == null || sig.isEmpty) {
      await _prefs?.remove(_keyTemplatesUploadSignature);
    } else {
      await _prefs?.setString(_keyTemplatesUploadSignature, sig);
    }
  }

  Future<void> clearTemplatesUploadProgress() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyTemplatesUploadOffset);
    await _prefs?.remove(_keyTemplatesUploadSignature);
  }

  /// Reset the template pull/push cursors so the NEXT sync re-pulls the account's
  /// templates in full. Keeps the local store + dirty/deleted queues intact —
  /// used on a guest→account upgrade where dirty guest templates must upload.
  Future<void> resetTemplateSyncCursors() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyTemplatesSyncVersion);
    await _prefs?.remove(_keyTemplatesLastSyncAt);
    await clearTemplatesUploadProgress();
  }

  /// Clear ALL template sync state (cursors + upload resume + dirty/deleted
  /// queues + per-id versions) for an account switch / sign-out, so the next
  /// account starts clean and never re-uploads the prior account's templates.
  Future<void> clearTemplateSyncState() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyTemplatesSyncVersion);
    await _prefs?.remove(_keyTemplatesLastSyncAt);
    await _prefs?.remove(_keyTemplatesDirtyIds);
    await _prefs?.remove(_keyTemplatesDeletedIds);
    await _prefs?.remove(_keyTemplatesVersionById);
    await clearTemplatesUploadProgress();
  }

  // ------- Templates per-id sync versions -------
  Future<Map<String, int>> getTemplatesVersionMap() async {
    if (_prefs == null) await init();
    final raw = _getMap<int>(_keyTemplatesVersionById);
    return Map<String, int>.from(raw);
  }

  Future<int?> getTemplateSyncVersion(String id) async {
    final map = await getTemplatesVersionMap();
    return map[id];
  }

  Future<void> setTemplateSyncVersion(String id, int version) async {
    if (_prefs == null) await init();
    final map = _getMap<int>(_keyTemplatesVersionById);
    map[id] = version;
    await _setMap(_keyTemplatesVersionById, map);
  }

  Future<void> removeTemplateSyncVersions(Iterable<String> ids) async {
    if (_prefs == null) await init();
    final map = _getMap<int>(_keyTemplatesVersionById);
    for (final id in ids) {
      map.remove(id);
    }
    if (map.isEmpty) {
      await _prefs?.remove(_keyTemplatesVersionById);
    } else {
      await _setMap(_keyTemplatesVersionById, map);
    }
  }

  // ------- Workout writeback mappings -------
  Future<Map<String, String>> getWorkoutWritebackMappings() async {
    if (_prefs == null) await init();
    final raw = _getMap<String>(_keyWorkoutWritebackMappings);
    return Map<String, String>.from(raw);
  }

  Future<void> upsertWorkoutWritebackMapping(
    String externalId,
    String uuid,
  ) async {
    if (_prefs == null) await init();
    final map = _getMap<String>(_keyWorkoutWritebackMappings);
    map[externalId] = uuid;
    await _setMap(_keyWorkoutWritebackMappings, map);
  }

  Future<void> removeWorkoutWritebackMapping(String externalId) async {
    if (_prefs == null) await init();
    final map = _getMap<String>(_keyWorkoutWritebackMappings);
    map.remove(externalId);
    if (map.isEmpty) {
      await _prefs?.remove(_keyWorkoutWritebackMappings);
    } else {
      await _setMap(_keyWorkoutWritebackMappings, map);
    }
  }

  Future<void> clearWorkoutWritebackMappings() async {
    if (_prefs == null) await init();
    await _prefs?.remove(_keyWorkoutWritebackMappings);
  }

  Future<void> setWorkoutWritebackEnabledIos(bool enabled) async {
    if (_prefs == null) await init();
    if (enabled) {
      await _prefs?.setBool(_keyWorkoutWritebackEnabledIos, true);
    } else {
      await _prefs?.remove(_keyWorkoutWritebackEnabledIos);
    }
  }

  Future<void> setWorkoutWritebackEnabledAndroid(bool enabled) async {
    if (_prefs == null) await init();
    if (enabled) {
      await _prefs?.setBool(_keyWorkoutWritebackEnabledAndroid, true);
    } else {
      await _prefs?.remove(_keyWorkoutWritebackEnabledAndroid);
    }
  }

  Future<bool> getWorkoutWritebackEnabledIos() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyWorkoutWritebackEnabledIos) ?? false;
  }

  Future<bool> getWorkoutWritebackEnabledAndroid() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyWorkoutWritebackEnabledAndroid) ?? false;
  }

  // ------- Background sync preference -------
  Future<bool> getBackgroundSyncEnabled() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyBackgroundSyncEnabled) ?? true;
  }

  Future<void> setBackgroundSyncEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyBackgroundSyncEnabled, value);
  }

  Future<void> setHealthPermissionsDenied(bool value) async {
    if (_prefs == null) await init();
    if (value) {
      await _prefs?.setBool(_keyHealthPermissionsDenied, true);
    } else {
      await _prefs?.remove(_keyHealthPermissionsDenied);
    }
  }

  Future<bool> getHealthPermissionsDenied() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyHealthPermissionsDenied) ?? false;
  }

  /// Number of consecutive health-permission request attempts that produced no
  /// granted type. Defaults to 0. See [_keyHealthPermissionRequestCount].
  Future<int> getHealthPermissionRequestCount() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyHealthPermissionRequestCount) ?? 0;
  }

  Future<void> setHealthPermissionRequestCount(int value) async {
    if (_prefs == null) await init();
    if (value <= 0) {
      await _prefs?.remove(_keyHealthPermissionRequestCount);
    } else {
      await _prefs?.setInt(_keyHealthPermissionRequestCount, value);
    }
  }

  // ------- Haptic feedback preference -------
  bool get hapticsEnabled => _prefs?.getBool(_keyHapticsEnabled) ?? true;

  Future<void> setHapticsEnabled(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyHapticsEnabled, value);
  }

  int get inactivityReminderMinutes {
    final stored = _prefs?.getInt(_keyInactivityReminderMinutes);
    if (stored == null) return 5;
    return stored.clamp(1, 60);
  }

  Future<void> setInactivityReminderMinutes(int minutes) async {
    if (_prefs == null) await init();
    final clamped = minutes.clamp(1, 60);
    await _prefs?.setInt(_keyInactivityReminderMinutes, clamped);
  }

  // ------- Debug mode preference -------
  Future<bool> getDebugMode() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyDebugMode) ?? false;
  }

  Future<void> setDebugMode(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyDebugMode, value);
  }

  // ------- Record tab preferences -------
  Future<int?> getRecordTimeGroupIndex() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyRecordTabGroup);
  }

  Future<void> setRecordTimeGroupIndex(int index) async {
    if (_prefs == null) await init();
    await _prefs?.setInt(_keyRecordTabGroup, index);
  }

  Future<bool> getRecordUse1Rm() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyRecordTabUse1Rm) ?? false;
  }

  Future<void> setRecordUse1Rm(bool use1rm) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyRecordTabUse1Rm, use1rm);
  }

  Future<int?> getRecordQuickRangeIndex() async {
    if (_prefs == null) await init();
    return _prefs?.getInt(_keyRecordTabQuickRange);
  }

  Future<void> setRecordQuickRangeIndex(int? index) async {
    if (_prefs == null) await init();
    if (index == null) {
      await _prefs?.remove(_keyRecordTabQuickRange);
    } else {
      await _prefs?.setInt(_keyRecordTabQuickRange, index);
    }
  }

  // ------- Exercise list: compact view -------
  Future<bool> getExerciseListCompact() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyExerciseListCompact) ?? true;
  }

  Future<void> setExerciseListCompact(bool compact) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyExerciseListCompact, compact);
  }

  // ------- Add-food flow: speed vs context -------
  /// Whether the add-food sheet runs in context mode (true): after each pick is
  /// staged it auto-opens the plate review so you can tweak as you go. Default
  /// false = speed: a pick stages and you stay in search for the next add.
  Future<bool> getAddFoodContextMode() async {
    if (_prefs == null) await init();
    return _prefs?.getBool(_keyAddFoodContextMode) ?? false;
  }

  Future<void> setAddFoodContextMode(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyAddFoodContextMode, value);
  }

  // ------- Telemetry -------
  /// Runtime opt-out for ALL client telemetry. Sync getter (mirrors the other
  /// sync gate flags) so [AnalyticsService.logEvent] can no-op without awaiting;
  /// `_prefs` is populated by the awaited `init()` during DI, before any event.
  bool get telemetryOptOut => _prefs?.getBool(_keyTelemetryOptOut) ?? false;

  Future<void> setTelemetryOptOut(bool value) async {
    if (_prefs == null) await init();
    await _prefs?.setBool(_keyTelemetryOptOut, value);
  }

  /// The raw per-install telemetry seed, or null before one is minted. Only the
  /// [AnalyticsService] reads this — and it only ever emits the seed's opaque
  /// SHA-256 hash, never this value.
  String? get telemetryInstallId => _prefs?.getString(_keyTelemetryInstallId);

  Future<void> setTelemetryInstallId(String value) async {
    if (_prefs == null) await init();
    await _prefs?.setString(_keyTelemetryInstallId, value);
  }
}
