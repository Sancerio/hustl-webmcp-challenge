import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_section.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/hustl_menu_button.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/services/theme_service.dart';
import '../../../../app/di/service_locator.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/widgets/sign_out_confirmation.dart';
import '../../../auth/presentation/widgets/account_sheet.dart';
import '../../../workout_logging/data/services/workout_sync_service.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/watch_bridge/watch_bridge_service.dart';
import '../../../../core/widgets/sync_prompt_card.dart';
import '../../../../core/utils/health_platform_labels.dart';
import '../../../health_sync/domain/repositories/health_metrics_repository.dart';
import '../../../health_sync/data/writeback/apple_health_duplicate_cleanup_service.dart';
import '../../../health_sync/data/writeback/workout_writeback_coordinator.dart';
import '../../../health_sync/domain/writeback/workout_write_service.dart';

/// Viewport width at and above which the settings sections reflow into two
/// columns (landscape tablet / desktop). Matches the shell's wide breakpoint.
const double _kSettingsWideBreakpoint = 900;

enum _AppleHealthCleanupMode { dryRun, delete }

enum _AppleHealthCleanupRange { last30Days, allTime }

class _AppleHealthCleanupAction {
  const _AppleHealthCleanupAction({required this.mode, required this.range});

  final _AppleHealthCleanupMode mode;
  final _AppleHealthCleanupRange range;
}

extension on _AppleHealthCleanupRange {
  String get label => switch (this) {
    _AppleHealthCleanupRange.last30Days => 'Last 30 days',
    _AppleHealthCleanupRange.allTime => 'All time',
  };

  DateTime start(DateTime now) => switch (this) {
    _AppleHealthCleanupRange.last30Days => now.subtract(
      const Duration(days: 30),
    ),
    _AppleHealthCleanupRange.allTime => DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    ),
  };
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<int> _inactivityOptions = [3, 5, 10, 15, 20, 30];
  bool _backgroundSyncEnabled = true;
  bool _hapticsEnabled = true;
  String? _version;
  static PackageInfo? _cachedInfo;
  bool _bgSyncLoaded = false;
  bool _hapticsLoaded = false;
  int _inactivityMinutes = 5;
  bool _inactivityLoaded = false;
  bool _checkInReminderEnabled = false;
  int _checkInReminderWeekday = DateTime.monday;
  int _checkInReminderHour = 9;
  int _checkInReminderMinute = 0;
  bool _checkInReminderLoaded = false;
  bool _versionLoaded = false;
  bool _debugMode = false;
  bool _debugLoaded = false;
  bool _debugVisible = false;
  bool _watchCompanionEnabled = false;
  bool? _watchCompanionOverride;
  bool _watchCompanionLoaded = false;
  bool _watchHeartRateRecordingEnabled = true;
  bool _watchHeartRateRecordingLoaded = false;
  bool _suggestNextSetTargets = true;
  bool _suggestNextSetTargetsLoaded = false;
  bool _weeklyTrainingRecapEnabled = false;
  bool _weeklyTrainingRecapLoaded = false;
  bool _aiCaptureConsent = false;
  bool _aiCaptureConsentLoaded = false;
  bool _showExternalInDay = true;
  bool _showExternalInDayLoaded = false;
  int _versionTapCount = 0;
  WorkoutWritebackCoordinator? _workoutWriteback;
  bool _workoutWritebackBusy = false;
  bool _appleHealthCleanupBusy = false;
  // Cached future for last sync date so it doesn't reload on every rebuild.
  late final Future<DateTime?> _lastSyncFuture =
      GetIt.instance<PreferencesService>().getWorkoutsLastSyncAt();

  // Cached future for health permissions status — must not be created in
  // build() or it would be re-evaluated on every rebuild.
  late final Future<HealthPermissionsStatus> _healthPermsFuture =
      GetIt.instance<HealthMetricsRepository>().getPermissionsStatus();

  @override
  void initState() {
    super.initState();
    _loadAllPreferences();
    if (GetIt.instance.isRegistered<WorkoutWritebackCoordinator>()) {
      final coordinator = GetIt.instance<WorkoutWritebackCoordinator>();
      _workoutWriteback = coordinator;
      unawaited(coordinator.init());
    }
  }

  /// Batch all preference loads into one Future.wait so initState triggers
  /// a single setState instead of up to 7 sequential rebuilds.
  Future<void> _loadAllPreferences() async {
    final prefs = GetIt.instance<PreferencesService>();
    try {
      final results = await Future.wait([
        prefs.getBackgroundSyncEnabled(), // 0
        Future.value(prefs.hapticsEnabled), // 1
        Future.value(prefs.inactivityReminderMinutes), // 2
        prefs.getDebugMode(), // 3
        prefs.getWatchCompanionEnabled(), // 4
        prefs.getWatchCompanionDebugOverride(), // 5
        prefs.getWatchHeartRateRecordingEnabled(), // 6
        _loadPackageInfo(), // 7
        prefs.getAiCaptureConsent(), // 8
        prefs.getNutritionCheckInReminderEnabled(), // 9
        prefs.getNutritionCheckInReminderWeekday(), // 10
        prefs.getNutritionCheckInReminderHour(), // 11
        prefs.getNutritionCheckInReminderMinute(), // 12
        Future.value(prefs.suggestNextSetTargets), // 13
        Future.value(prefs.weeklyTrainingRecapEnabled), // 14
        prefs.getShowExternalWorkoutsInDay(), // 15
      ]);

      if (!mounted) return;

      final baseWatchEnabled = WatchBridgeService.envEnabled
          ? true
          : (results[4] as bool);
      final watchOverride = results[5] as bool?;

      setState(() {
        _backgroundSyncEnabled = results[0] as bool;
        _bgSyncLoaded = true;
        _hapticsEnabled = results[1] as bool;
        _hapticsLoaded = true;
        _inactivityMinutes = results[2] as int;
        _inactivityLoaded = true;
        _debugMode = results[3] as bool;
        _debugLoaded = true;
        _debugVisible = _debugMode;
        _watchCompanionEnabled = watchOverride ?? baseWatchEnabled;
        _watchCompanionOverride = watchOverride;
        _watchCompanionLoaded = true;
        _watchHeartRateRecordingEnabled = results[6] as bool;
        _watchHeartRateRecordingLoaded = true;
        _version = results[7] as String?;
        _versionLoaded = true;
        _aiCaptureConsent = results[8] as bool;
        _aiCaptureConsentLoaded = true;
        _checkInReminderEnabled = results[9] as bool;
        _checkInReminderWeekday = results[10] as int;
        _checkInReminderHour = results[11] as int;
        _checkInReminderMinute = results[12] as int;
        _checkInReminderLoaded = true;
        _suggestNextSetTargets = results[13] as bool;
        _suggestNextSetTargetsLoaded = true;
        _weeklyTrainingRecapEnabled = results[14] as bool;
        _weeklyTrainingRecapLoaded = true;
        _showExternalInDay = results[15] as bool;
        _showExternalInDayLoaded = true;
      });
    } catch (e) {
      debugPrint('Settings: failed to batch-load preferences: $e');
      if (!mounted) return;
      setState(() {
        _bgSyncLoaded = true;
        _hapticsLoaded = true;
        _inactivityLoaded = true;
        _debugLoaded = true;
        _watchCompanionLoaded = true;
        _watchHeartRateRecordingLoaded = true;
        _aiCaptureConsentLoaded = true;
        _checkInReminderLoaded = true;
        _suggestNextSetTargetsLoaded = true;
        _weeklyTrainingRecapLoaded = true;
        _showExternalInDayLoaded = true;
        _versionLoaded = true;
        _version ??= 'Unknown';
      });
    }
  }

  Future<String?> _loadPackageInfo() async {
    try {
      final info = _cachedInfo ??= await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      debugPrint('Failed to load app version: $e');
      return 'Unknown';
    }
  }

  // ------- Weekly nutrition check-in reminder -------
  static const List<int> _weekdayOptions = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  static const List<String> _weekdayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String _weekdayLabel(int weekday) =>
      _weekdayLabels[(weekday - DateTime.monday) % 7];

  String get _checkInReminderTimeLabel {
    final t = TimeOfDay(
      hour: _checkInReminderHour,
      minute: _checkInReminderMinute,
    );
    return t.format(context);
  }

  Future<void> _setCheckInReminderEnabled(bool value) async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setNutritionCheckInReminderEnabled(value);
    if (value) {
      await NotificationService().scheduleWeeklyCheckIn(
        weekday: _checkInReminderWeekday,
        hour: _checkInReminderHour,
        minute: _checkInReminderMinute,
      );
    } else {
      await NotificationService().cancelWeeklyCheckIn();
    }
    if (!mounted) return;
    setState(() => _checkInReminderEnabled = value);
  }

  Future<void> _setCheckInReminderWeekday(int weekday) async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setNutritionCheckInReminderWeekday(weekday);
    if (_checkInReminderEnabled) {
      await NotificationService().scheduleWeeklyCheckIn(
        weekday: weekday,
        hour: _checkInReminderHour,
        minute: _checkInReminderMinute,
      );
    }
    if (!mounted) return;
    setState(() => _checkInReminderWeekday = weekday);
  }

  Future<void> _pickCheckInReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _checkInReminderHour,
        minute: _checkInReminderMinute,
      ),
    );
    if (picked == null) return;
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setNutritionCheckInReminderTime(picked.hour, picked.minute);
    if (_checkInReminderEnabled) {
      await NotificationService().scheduleWeeklyCheckIn(
        weekday: _checkInReminderWeekday,
        hour: picked.hour,
        minute: picked.minute,
      );
    }
    if (!mounted) return;
    setState(() {
      _checkInReminderHour = picked.hour;
      _checkInReminderMinute = picked.minute;
    });
  }

  // ------- Weekly training recap reminder -------
  /// One gentle nudge on Sundays at 18:00 that lands on the Progress tab.
  /// Mirrors the nutrition check-in's opt-in lifecycle: ON schedules, OFF
  /// cancels, and the pref is the source of truth (no auto-reschedule on start,
  /// matching the check-in — the Settings toggle owns the schedule).
  Future<void> _setWeeklyTrainingRecapEnabled(bool value) async {
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setWeeklyTrainingRecapEnabled(value);
    if (value) {
      await NotificationService().scheduleWeeklyTrainingRecap(
        weekday: DateTime.sunday,
        hour: 18,
        minute: 0,
      );
    } else {
      await NotificationService().cancelWeeklyTrainingRecap();
    }
    if (!mounted) return;
    setState(() => _weeklyTrainingRecapEnabled = value);
  }

  Future<void> _toggleWorkoutWriteback(bool enable) async {
    final coordinator = _workoutWriteback;
    if (coordinator == null) return;
    if (_workoutWritebackBusy) return;
    final fallbackPlatform = Theme.of(context).platform;
    if (mounted) {
      setState(() {
        _workoutWritebackBusy = true;
      });
    }
    try {
      await coordinator.toggleEnabled(enable);
      if (!mounted) return;
      final updated = coordinator.state.value;
      if (enable && (!updated.enabled || !updated.permissionsGranted)) {
        final provider = switch (updated.capability?.platform) {
          WorkoutWritePlatform.iosHealthKit => 'Apple Health',
          WorkoutWritePlatform.androidHealthConnect => 'Health Connect',
          _ => healthPlatformLabel(platform: fallbackPlatform),
        };
        HustlSnack.show(
          context,
          'Permission required: enable Workouts for Hustl in $provider to write workouts.',
          variant: HustlSnackVariant.warning,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _workoutWritebackBusy = false;
        });
      }
    }
  }

  Future<void> _promptAppleHealthDuplicateCleanup() async {
    if (_appleHealthCleanupBusy) return;
    var range = _AppleHealthCleanupRange.last30Days;
    final choice = await showDialog<_AppleHealthCleanupAction>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Clean Apple Health duplicates'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Removes duplicate workouts created by Hustl (matching start/end times within ~90 seconds). '
                      'Try Dry run first to preview.',
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<_AppleHealthCleanupRange>(
                      value: range,
                      isExpanded: true,
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => range = value);
                      },
                      items: [
                        for (final value in _AppleHealthCleanupRange.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => context.pop(
                    _AppleHealthCleanupAction(
                      mode: _AppleHealthCleanupMode.dryRun,
                      range: range,
                    ),
                  ),
                  child: const Text('Dry run'),
                ),
                FilledButton(
                  onPressed: () => context.pop(
                    _AppleHealthCleanupAction(
                      mode: _AppleHealthCleanupMode.delete,
                      range: range,
                    ),
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || choice == null) return;
    await _runAppleHealthDuplicateCleanup(
      dryRun: choice.mode == _AppleHealthCleanupMode.dryRun,
      range: choice.range,
    );
  }

  Future<void> _runAppleHealthDuplicateCleanup({
    required bool dryRun,
    required _AppleHealthCleanupRange range,
  }) async {
    if (_appleHealthCleanupBusy) return;
    setState(() => _appleHealthCleanupBusy = true);
    try {
      final now = DateTime.now();
      final result = await AppleHealthDuplicateCleanupService(
        preferences: GetIt.instance<PreferencesService>(),
      ).cleanupDuplicates(start: range.start(now), end: now, dryRun: dryRun);

      if (!mounted) return;

      final verb = dryRun ? 'Would delete' : 'Deleted';
      final message = !result.supported
          ? 'Apple Health cleanup is only available on iOS.'
          : !result.permissionsGranted
          ? 'Apple Health permissions were not granted.'
          : '$verb ${result.deletedCount} workouts (${range.label}) '
                '(groups: ${result.duplicateGroupCount}, '
                'Hustl: ${result.hustlWorkoutCount}, '
                'scanned: ${result.scannedCount}).'
                '${result.errors.isEmpty ? '' : ' Errors: ${result.errors.length}.'}';

      if (result.errors.isNotEmpty) {
        debugPrint(
          '[AppleHealthCleanup] ${result.errors.take(5).join(' | ')}'
          '${result.errors.length > 5 ? ' | …' : ''}',
        );
      }

      HustlSnack.show(context, message);
    } finally {
      if (mounted) {
        setState(() => _appleHealthCleanupBusy = false);
      }
    }
  }

  void _onVersionTap() {
    if (_debugVisible) return;
    _versionTapCount++;
    if (_versionTapCount >= 5) {
      setState(() {
        _debugVisible = true;
      });
      if (mounted) {
        HustlSnack.show(
          context,
          'Debug mode unlocked',
          variant: HustlSnackVariant.success,
        );
      }
    }
  }

  String _formatMinutes(int minutes) {
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  /// Shows a confirmation bottom sheet before signing out.
  Future<void> _confirmSignOut(BuildContext context) async {
    // Capture bloc reference before the async gap to satisfy the lint.
    final authBloc = context.read<AuthBloc>();
    final confirmed = await confirmSignOut(context);
    if (!mounted || !confirmed) return;
    authBloc.add(AuthSignOutRequested());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeService = getIt<ThemeService>();
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final showHapticsToggle =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final watchSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    // Each settings section is built as a self-contained block (header + card).
    // Below the wide breakpoint these stack in one column (byte-for-byte the
    // original ListView order). At and above it, the blocks reflow into two
    // side-by-side columns within the same scroll view.
    final accountSection = _SettingsSection(
      children: [
        const SectionHeader('Account'),
        BlocBuilder<AuthBloc, AuthState>(
          buildWhen: (prev, curr) =>
              (prev is AuthAuthenticated) != (curr is AuthAuthenticated),
          builder: (context, state) {
            if (state is! AuthAuthenticated) {
              return SyncPromptCard(
                title: 'Sign in to sync',
                subtitle:
                    'Back up your workout history and sync across devices.',
                ctaLabel: 'Sign in',
                onCtaPressed: () => showLoginSheet(context),
                showBenefits: true,
              );
            }
            final user = state.user;
            return _SectionCard(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user.photoUrl != null
                        ? NetworkImage(user.photoUrl!)
                        : null,
                    child: user.photoUrl == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(user.displayName ?? 'Signed in'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  // Destructive action — confirm before executing.
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            );
          },
        ),
      ],
    );

    final appearanceSection = _SettingsSection(
      children: [
        const SectionHeader('Appearance'),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeService.themeMode,
          builder: (context, mode, _) {
            return _SectionCard(
              children: [
                RadioGroup<ThemeMode>(
                  groupValue: mode,
                  onChanged: (m) {
                    if (m == null) return;
                    themeService.setThemeMode(m);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.system,
                        title: Text('Use device setting'),
                        secondary: Icon(Icons.settings_suggest_outlined),
                      ),
                      Divider(height: 1),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.light,
                        title: Text('Light'),
                        secondary: Icon(Icons.light_mode_outlined),
                      ),
                      Divider(height: 1),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.dark,
                        title: Text('Dark'),
                        secondary: Icon(Icons.dark_mode_outlined),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );

    final cloudSyncSection = _SettingsSection(
      children: [
        const SectionHeader('Cloud Sync'),
        BlocBuilder<AuthBloc, AuthState>(
          buildWhen: (prev, curr) =>
              (prev is AuthAuthenticated) != (curr is AuthAuthenticated),
          builder: (context, state) {
            final authed = state is AuthAuthenticated;
            return _SectionCard(
              children: [
                FutureBuilder<DateTime?>(
                  future: _lastSyncFuture,
                  builder: (context, snapshot) {
                    final last = snapshot.data;
                    final baseSubtitle = last == null
                        ? 'No sync yet'
                        : 'Last sync: ${DateFormat('yyyy-MM-dd HH:mm').format(last)}';
                    return ValueListenableBuilder<SyncProgress?>(
                      valueListenable:
                          GetIt.instance<WorkoutSyncService>().progress,
                      builder: (context, prog, _) {
                        final syncing = prog != null;
                        final subtitle = syncing
                            ? (prog.total > 0
                                  ? 'Syncing ${prog.completed}/${prog.total}'
                                  : 'Syncing...')
                            : baseSubtitle;
                        Widget trailing;
                        if (!authed) {
                          // A clearly DISABLED affordance — not a bare line of
                          // text that looks tappable but isn't. The single
                          // actionable sign-in CTA is the Account card above;
                          // the reason lives in this row's subtitle.
                          trailing = const FilledButton(
                            onPressed: null,
                            child: Text('Sync now'),
                          );
                        } else {
                          trailing = FilledButton(
                            onPressed: syncing
                                ? null
                                : () async {
                                    try {
                                      await GetIt.instance<WorkoutSyncService>()
                                          .syncNow();
                                      if (context.mounted) {
                                        HustlSnack.show(
                                          context,
                                          'Sync complete',
                                          variant: HustlSnackVariant.success,
                                        );
                                      }
                                      setState(() {});
                                    } catch (e) {
                                      if (context.mounted) {
                                        HustlSnack.show(
                                          context,
                                          'Couldn\'t sync your workouts. Please try again.',
                                          variant: HustlSnackVariant.error,
                                        );
                                      }
                                    }
                                  },
                            child: Text(syncing ? 'Syncing...' : 'Sync now'),
                          );
                        }
                        return Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.cloud_sync_outlined),
                              title: const Text('Sync workout history'),
                              subtitle: Text(
                                authed
                                    ? subtitle
                                    : 'Sign in to enable cloud sync',
                              ),
                              trailing: trailing,
                            ),
                            if (syncing)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.x2,
                                  vertical: AppSpacing.x1,
                                ),
                                child: LinearProgressIndicator(
                                  value: prog.total > 0
                                      ? prog.completed / prog.total
                                      : null,
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
                if (authed) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.autorenew_outlined),
                    title: const Text('Background sync'),
                    subtitle: const Text('Runs periodically with backoff'),
                    trailing: _bgSyncLoaded
                        ? Switch(
                            value: _backgroundSyncEnabled,
                            onChanged: (value) async {
                              final prefs =
                                  GetIt.instance<PreferencesService>();
                              await prefs.setBackgroundSyncEnabled(value);
                              final svc = GetIt.instance<WorkoutSyncService>();
                              if (value) {
                                svc.startAutoSync();
                              } else {
                                svc.stopAutoSync();
                              }
                              setState(() {
                                _backgroundSyncEnabled = value;
                              });
                            },
                          )
                        : const AppSkeleton(width: 52, height: 32),
                  ),
                  if (showHapticsToggle) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.vibration),
                      title: const Text('Haptic feedback'),
                      subtitle: const Text('Vibrate on key actions'),
                      trailing: _hapticsLoaded
                          ? Switch(
                              value: _hapticsEnabled,
                              onChanged: (value) async {
                                final prefs =
                                    GetIt.instance<PreferencesService>();
                                await prefs.setHapticsEnabled(value);
                                setState(() => _hapticsEnabled = value);
                                if (value) {
                                  await Haptics.maybeMediumImpact();
                                }
                              },
                            )
                          : const AppSkeleton(width: 52, height: 32),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ],
    );

    final integrationsSection = _SettingsSection(
      children: [
        const SectionHeader('Integrations'),
        _SectionCard(
          children: [
            FutureBuilder<HealthPermissionsStatus>(
              future: _healthPermsFuture,
              builder: (context, snapshot) {
                final providerLabel = healthPlatformLabel(
                  platform: Theme.of(context).platform,
                );
                String subtitle;
                VoidCallback? onTap;
                if (snapshot.hasError) {
                  subtitle = 'Unable to determine health status';
                  onTap = () => GoRouter.of(context).push('/health');
                } else {
                  final status = snapshot.data;
                  final available = status?.isServiceAvailable ?? true;
                  final connected = status?.hasPermissions ?? false;
                  final denied = status?.deniedPermanently ?? false;
                  if (!available) {
                    subtitle = 'Not available on this device';
                    onTap = null;
                  } else if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    subtitle = 'Checking status...';
                    onTap = null;
                  } else if (connected) {
                    subtitle = 'Connected · tap to view dashboard';
                    onTap = () => GoRouter.of(context).push('/health');
                  } else if (denied) {
                    subtitle = 'Permissions denied · tap to retry';
                    onTap = () => GoRouter.of(context).push('/health');
                  } else {
                    subtitle = 'Connect $providerLabel';
                    onTap = () => GoRouter.of(context).push('/health');
                  }
                }

                return ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: const Text('Health integrations'),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onTap,
                );
              },
            ),
            if (_workoutWriteback != null) ...[
              const Divider(height: 1),
              ValueListenableBuilder<WorkoutWritebackState>(
                valueListenable: _workoutWriteback!.state,
                builder: (context, writeback, _) {
                  final capability = writeback.capability;
                  final capabilityKnown = capability != null;
                  final supported = capability?.supported ?? false;
                  final enabled = supported && writeback.enabled;
                  final queueLen = writeback.queueLength;

                  String subtitle;
                  if (!capabilityKnown) {
                    subtitle = 'Checking support…';
                  } else if (!supported) {
                    subtitle = 'Not supported on this device';
                  } else if (!enabled) {
                    final provider = switch (capability.platform) {
                      WorkoutWritePlatform.iosHealthKit => 'Apple Health',
                      WorkoutWritePlatform.androidHealthConnect =>
                        'Health Connect',
                      WorkoutWritePlatform.unsupported => 'Health',
                    };
                    subtitle =
                        'Off · enable to write completed workouts to $provider';
                  } else if (!writeback.permissionsGranted) {
                    subtitle = 'Permissions missing · toggle to reconnect';
                  } else if (queueLen > 0) {
                    subtitle =
                        'Syncing $queueLen workout${queueLen == 1 ? '' : 's'}';
                  } else {
                    final provider = switch (capability.platform) {
                      WorkoutWritePlatform.iosHealthKit => 'Apple Health',
                      WorkoutWritePlatform.androidHealthConnect =>
                        'Health Connect',
                      WorkoutWritePlatform.unsupported => 'Health',
                    };
                    subtitle = 'On · writes completed workouts to $provider';
                  }

                  return ListTile(
                    leading: const Icon(Icons.sync_outlined),
                    title: const Text('Write workouts to Health'),
                    subtitle: Text(subtitle),
                    trailing: Switch(
                      value: enabled,
                      onChanged:
                          (!capabilityKnown ||
                              !supported ||
                              _workoutWritebackBusy)
                          ? null
                          : (value) => _toggleWorkoutWriteback(value),
                    ),
                    onTap:
                        (!capabilityKnown ||
                            !supported ||
                            _workoutWritebackBusy)
                        ? null
                        : () => _toggleWorkoutWriteback(!enabled),
                  );
                },
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.directions_run_outlined),
              title: const Text('Show workouts from other apps in your day'),
              subtitle: const Text(
                'Lets the day’s strain receipt itemize workouts imported from '
                'other apps alongside your Hustl sessions.',
              ),
              trailing: _showExternalInDayLoaded
                  ? Switch(
                      value: _showExternalInDay,
                      onChanged: (value) async {
                        final prefs = GetIt.instance<PreferencesService>();
                        await prefs.setShowExternalWorkoutsInDay(value);
                        if (!mounted) return;
                        setState(() => _showExternalInDay = value);
                      },
                    )
                  : const AppSkeleton(width: 52, height: 32),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI meal capture'),
              subtitle: const Text(
                'Use Google Gemini to estimate macros from a photo or '
                'description.',
              ),
              trailing: _aiCaptureConsentLoaded
                  ? Switch(
                      value: _aiCaptureConsent,
                      onChanged: (value) async {
                        final prefs = GetIt.instance<PreferencesService>();
                        await prefs.setAiCaptureConsent(value);
                        if (!mounted) return;
                        setState(() => _aiCaptureConsent = value);
                      },
                    )
                  : const AppSkeleton(width: 52, height: 32),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Connected AI apps'),
              subtitle: const Text(
                'Manage which AI apps (Claude, ChatGPT, Codex) can read your '
                'data or propose changes you review — the single place that '
                'controls their access.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/connections'),
            ),
          ],
        ),
      ],
    );

    final workoutSection = _SettingsSection(
      children: [
        const SectionHeader('Workout'),
        _SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Inactivity reminder'),
              subtitle: Text(
                _inactivityLoaded
                    ? 'Notifies you after '
                          '${_formatMinutes(_inactivityMinutes)} of inactivity'
                    : 'Notifies you if your workout is idle',
              ),
              trailing: _inactivityLoaded
                  ? DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('inactivityDurationDropdown'),
                        value: _inactivityMinutes,
                        items: _inactivityOptions
                            .map(
                              (minutes) => DropdownMenuItem<int>(
                                value: minutes,
                                child: Text(_formatMinutes(minutes)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          final prefs = GetIt.instance<PreferencesService>();
                          await prefs.setInactivityReminderMinutes(value);
                          if (!mounted) return;
                          setState(() {
                            _inactivityMinutes = value;
                          });
                        },
                      ),
                    )
                  : const AppSkeleton(width: 112, height: 28),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Suggest next-set targets'),
              subtitle: const Text('Based on your previous session'),
              trailing: _suggestNextSetTargetsLoaded
                  ? Switch(
                      value: _suggestNextSetTargets,
                      onChanged: (value) async {
                        final prefs = GetIt.instance<PreferencesService>();
                        await prefs.setSuggestNextSetTargets(value);
                        if (!mounted) return;
                        setState(() {
                          _suggestNextSetTargets = value;
                        });
                      },
                    )
                  : const AppSkeleton(width: 52, height: 32),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Weekly training recap'),
              subtitle: const Text('One gentle nudge on Sundays'),
              trailing: _weeklyTrainingRecapLoaded
                  ? Switch(
                      value: _weeklyTrainingRecapEnabled,
                      onChanged: _setWeeklyTrainingRecapEnabled,
                    )
                  : const AppSkeleton(width: 52, height: 32),
            ),
            if (watchSupported) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('Auto-record heart rate on Apple Watch'),
                subtitle: const Text(
                  'Starts watch recording automatically for new workouts.',
                ),
                trailing: _watchHeartRateRecordingLoaded
                    ? Switch(
                        value: _watchHeartRateRecordingEnabled,
                        onChanged: (value) async {
                          final prefs = GetIt.instance<PreferencesService>();
                          await prefs.setWatchHeartRateRecordingEnabled(value);
                          if (!mounted) return;
                          setState(() {
                            _watchHeartRateRecordingEnabled = value;
                          });
                        },
                      )
                    : const AppSkeleton(width: 52, height: 32),
              ),
            ],
          ],
        ),
      ],
    );

    final nutritionSection = _SettingsSection(
      children: [
        const SectionHeader('Nutrition'),
        _SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Weekly check-in reminder'),
              subtitle: Text(
                _checkInReminderEnabled
                    ? 'Every ${_weekdayLabel(_checkInReminderWeekday)} '
                          'at $_checkInReminderTimeLabel'
                    : 'A gentle weekly nudge to review your targets',
              ),
              trailing: _checkInReminderLoaded
                  ? Switch(
                      value: _checkInReminderEnabled,
                      onChanged: _setCheckInReminderEnabled,
                    )
                  : const AppSkeleton(width: 52, height: 32),
            ),
            if (_checkInReminderEnabled) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('Day'),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _checkInReminderWeekday,
                    items: _weekdayOptions
                        .map(
                          (w) => DropdownMenuItem<int>(
                            value: w,
                            child: Text(_weekdayLabel(w)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _setCheckInReminderWeekday(value);
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Time'),
                trailing: Text(
                  _checkInReminderTimeLabel,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _pickCheckInReminderTime,
              ),
            ],
          ],
        ),
      ],
    );

    final dataImportSection = _SettingsSection(
      children: [
        const SectionHeader('Data & Import'),
        _SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.import_export),
              title: const Text('Import / export data'),
              subtitle: const Text('Strong CSV import, export, and guide'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/import-export'),
            ),
          ],
        ),
      ],
    );

    final legalSection = _SettingsSection(
      children: [
        const SectionHeader('Legal & Support'),
        _SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.restaurant_menu_outlined),
              title: const Text('Food data attribution'),
              subtitle: const Text('USDA FoodData Central'),
              onTap: _showFoodDataAttribution,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.source_outlined),
              title: const Text('Data sources'),
              subtitle: const Text('Open Food Facts (ODbL) · USDA'),
              onTap: _showDataSources,
            ),
          ],
        ),
      ],
    );

    final footerSection = _SettingsSection(
      children: [
        const SizedBox(height: AppSpacing.x3),
        _versionLoaded
            ? GestureDetector(
                onTap: _onVersionTap,
                child: Text(
                  'Version $_version',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              )
            : const Center(child: AppSkeleton(width: 120, height: 12)),
        if (_debugVisible) ...[
          const SectionHeader('Debug'),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Enable debug mode'),
                trailing: _debugLoaded
                    ? Switch(
                        value: _debugMode,
                        onChanged: (value) async {
                          final prefs = GetIt.instance<PreferencesService>();
                          await prefs.setDebugMode(value);
                          setState(() => _debugMode = value);
                        },
                      )
                    : const AppSkeleton(width: 52, height: 32),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.watch_outlined),
                title: const Text('Apple Watch companion (debug)'),
                subtitle: watchSupported
                    ? Text(
                        WatchBridgeService.envEnabled
                            ? (_watchCompanionOverride == null
                                  ? 'Default ON (production). Toggle to override.'
                                  : 'Overridden for this device.')
                            : 'Toggle stored per device (dev builds).',
                      )
                    : const Text('Available on iOS only'),
                trailing: _watchCompanionLoaded
                    ? Switch(
                        value: _watchCompanionEnabled,
                        onChanged: watchSupported
                            ? (value) async {
                                final prefs =
                                    GetIt.instance<PreferencesService>();
                                if (WatchBridgeService.envEnabled) {
                                  await prefs.setWatchCompanionDebugOverride(
                                    value ? null : false,
                                  );
                                } else {
                                  await prefs.setWatchCompanionEnabled(value);
                                  await prefs.setWatchCompanionDebugOverride(
                                    null,
                                  );
                                }
                                if (!mounted) return;
                                setState(() {
                                  _watchCompanionEnabled = value;
                                  _watchCompanionOverride =
                                      WatchBridgeService.envEnabled
                                      ? (value ? null : false)
                                      : null;
                                });
                                if (GetIt.instance
                                    .isRegistered<WatchBridgeService>()) {
                                  // ignore: discarded_futures
                                  GetIt.instance<WatchBridgeService>()
                                      .refreshEnabled();
                                }
                              }
                            : null,
                      )
                    : const AppSkeleton(width: 52, height: 32),
              ),
              if (_debugMode && isIos) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Clean Apple Health duplicate workouts'),
                  subtitle: Text(
                    _appleHealthCleanupBusy
                        ? 'Running...'
                        : 'Scans a selected range and removes Hustl duplicates',
                  ),
                  trailing: _appleHealthCleanupBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _appleHealthCleanupBusy
                      ? null
                      : _promptAppleHealthDuplicateCleanup,
                ),
              ],
            ],
          ),
        ],
      ],
    );

    // Wave: on wide viewports the grouped sections reflow into two balanced
    // columns; below the breakpoint they stay one column (original order).
    final isWide = MediaQuery.sizeOf(context).width >= _kSettingsWideBreakpoint;

    final Widget body;
    if (isWide) {
      // Left column carries identity, appearance, sync, and integrations;
      // right column carries workout, data, legal, and the footer/debug group.
      final leftSections = <Widget>[
        accountSection,
        appearanceSection,
        cloudSyncSection,
        integrationsSection,
      ];
      final rightSections = <Widget>[
        workoutSection,
        nutritionSection,
        dataImportSection,
        legalSection,
        footerSection,
      ];
      body = ListView(
        padding: const EdgeInsets.only(
          bottom: kBottomNavigationBarHeight + AppSpacing.x3,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: leftSections,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rightSections,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(
          bottom: kBottomNavigationBarHeight + AppSpacing.x3,
        ),
        children: [
          accountSection,
          appearanceSection,
          cloudSyncSection,
          integrationsSection,
          workoutSection,
          nutritionSection,
          dataImportSection,
          legalSection,
          footerSection,
        ],
      );
    }

    return MainScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const HustlMenuButton(),
        title: const Text('Settings'),
        centerTitle: true,
      ),
      child: body,
    );
  }

  Future<void> _showFoodDataAttribution() async {
    final url = Uri.parse('https://fdc.nal.usda.gov/');
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x1,
            AppSpacing.x2,
            AppSpacing.x3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Food data attribution',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                'Food data is provided by USDA FoodData Central.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              FilledButton.icon(
                onPressed: () async {
                  if (!await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  )) {
                    if (!context.mounted) return;
                    HustlSnack.show(
                      context,
                      'Couldn\'t open the link',
                      variant: HustlSnackVariant.warning,
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open FoodData Central'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Settings > Data sources: the persistent ODbL / public-domain attribution
  /// surface. ODbL requires a durable credit for cached Open Food Facts data;
  /// USDA FoodData Central is public domain but credited alongside for clarity.
  Future<void> _showDataSources() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x1,
            AppSpacing.x2,
            AppSpacing.x3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Data sources',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                'Branded food data from Open Food Facts (ODbL). '
                'Generic foods from USDA FoodData Central (public domain).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Wave I (§12.1): a grouped settings card — related rows wrapped in a rounded
/// surface card with hairline dividers, so each section reads as a premium iOS
/// grouped object rather than a flat admin ledger. The card supplies its own
/// horizontal inset, so the enclosed [ListTile]s drop their default horizontal
/// content padding to stay flush with the card edge.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme.merge(
      contentPadding: EdgeInsets.zero,
      child: SectionList(
        card: true,
        dividers: false,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        children: children,
      ),
    );
  }
}

/// A self-contained settings section (its [SectionHeader] plus the grouped
/// card/content beneath it) rendered as a single vertical block. Stacking
/// these in a column reproduces the original flat-ListView order exactly, and
/// lets the wide layout move whole sections between columns without splitting a
/// header from its card.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
