import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as dev;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import '../../features/workout_logging/domain/services/rest_timer_service.dart';
import '../../main.dart';
import '../navigation/workout_minimize_intent.dart';
import 'notification_schedule_time.dart';

// Boxing bell sample sourced from "Boxing Bell" by Benboncan (CC BY 4.0).
const String _restCompleteChannelId = 'rest_timer_channel_bell';
const String _restCompleteChannelName = 'Rest Timer';
const String _restCompleteChannelDescription =
    'Notifications for rest timer completion';
const String _restCompleteSilentChannelId = 'rest_timer_channel_silent';
const String _restCompleteSilentChannelName = 'Rest Timer (Silent)';
const String _restCompleteSilentChannelDescription =
    'Foreground rest timer alerts without sound';
const String _restBellAndroidSound = 'rest_bell';
const String _restBellIosSound = 'rest_bell.wav';

// Weekly nutrition check-in reminder. A single repeating, low-key notification
// (default importance, passive on iOS) — a soft habit nudge, never an alarm.
const String _checkInChannelId = 'nutrition_checkin_channel';
const String _checkInChannelName = 'Weekly check-in';
const String _checkInChannelDescription =
    'A gentle weekly reminder to review your nutrition check-in';

/// Stable id for the repeating weekly check-in notification, so re-scheduling is
/// idempotent (overwrites in place) and cancel is unambiguous.
const int kWeeklyCheckInId = 1010;

// Weekly training recap reminder. Mirrors the nutrition check-in exactly — a
// single repeating, low-key notification (default importance, passive on iOS)
// that lands on the Progress tab. One gentle nudge a week, never an alarm.
const String _trainingRecapChannelId = 'training_recap_channel';
const String _trainingRecapChannelName = 'Weekly training recap';
const String _trainingRecapChannelDescription =
    'A gentle weekly reminder to review your training week';

/// Stable id for the repeating weekly training recap notification, so
/// re-scheduling is idempotent (overwrites in place) and cancel is unambiguous.
/// Distinct from [kWeeklyCheckInId] so the two weekly nudges never collide.
const int kWeeklyTrainingRecapId = 1011;

// "Your connected AI logged a meal/workout" — a calm, default-importance alert
// the poller raises when it detects an AUTO-applied log, deep-linking to undo.
const String _aiLogChannelId = 'ai_log_channel';
const String _aiLogChannelName = 'Assistant logging';
const String _aiLogChannelDescription =
    'When a connected AI logs food or a workout for you';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _restLiveActivityChannel = MethodChannel(
    'com.hustl.app/rest_live_activity',
  );
  bool _initialized = false;
  Future<void>? _initFuture;
  int _ongoingNotificationGeneration = 0;
  DateTime? _workoutStartTime;
  String? _currentExerciseName;
  AudioPlayer? _bellPlayer;
  bool _iosRestBellReady = false;

  Future<void> init() {
    if (_initialized) return Future.value();
    return _initFuture ??= _initInternal();
  }

  Future<void> _initInternal() async {
    try {
      // Notifications are unsupported on web via this plugin; no-op safely.
      if (kIsWeb) {
        _initialized = true;
        return;
      }

      // Only initialize the plugin on supported platforms (Android/iOS).
      if (!Platform.isAndroid && !Platform.isIOS) {
        _initialized = true;
        return;
      }

      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('ic_stat_hustl');
      final DarwinInitializationSettings iosInit = DarwinInitializationSettings(
        // Do not request on app start; we will request when a workout starts.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        onDidReceiveLocalNotification: (id, title, body, payload) async {},
      );

      final InitializationSettings initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse:
            (NotificationResponse response) async {
              await _handleNotificationTap(response);
            },
      );

      if (Platform.isIOS) {
        await _prepareIosRestBellIfNeeded();
      }

      // Initialize timezone data for scheduled notifications
      tz.initializeTimeZones();

      // On Android 13+, notifications require runtime permission via OS prompt.
      // We explicitly request when starting a workout, not at app launch.
      _initialized = true;

      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _restCompleteChannelId,
            _restCompleteChannelName,
            description: _restCompleteChannelDescription,
            importance: Importance.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(_restBellAndroidSound),
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _restCompleteSilentChannelId,
            _restCompleteSilentChannelName,
            description: _restCompleteSilentChannelDescription,
            importance: Importance.high,
            playSound: false,
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.notification,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            'rest_timer_ongoing_channel',
            'Rest Timer (Ongoing)',
            description: 'Ongoing countdown for rest timer',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            'sync_channel',
            'Background Sync',
            description: 'Notifications for workout data sync status',
            importance: Importance.defaultImportance,
            playSound: false,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            'inactivity_channel',
            'Inactivity Reminder',
            description: 'Notifications when workout remains inactive',
            importance: Importance.defaultImportance,
            playSound: true,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            'workout_ongoing_channel',
            'Workout (Ongoing)',
            description: 'Shows the current exercise and workout duration',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _checkInChannelId,
            _checkInChannelName,
            description: _checkInChannelDescription,
            // Default importance, no custom sound: a calm nudge that Focus/DND
            // can hold without eroding trust — never time-sensitive.
            importance: Importance.defaultImportance,
            playSound: true,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _aiLogChannelId,
            _aiLogChannelName,
            description: _aiLogChannelDescription,
            importance: Importance.defaultImportance,
            playSound: true,
          ),
        );
      }
    } finally {
      _initFuture = null;
    }
  }

  /// Request notification permissions at an appropriate time (e.g., when a
  /// workout starts). Returns true if notifications are enabled/granted.
  Future<bool> ensurePermissionsForWorkout() async {
    await init();

    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        // Check current status first
        final enabled = await android?.areNotificationsEnabled();
        if (enabled == true) return true;

        // Try to request (Android 13+). Different plugin versions expose
        // either requestPermission or requestNotificationsPermission.
        bool granted = false;
        try {
          granted =
              await (android as dynamic)?.requestPermission() as bool? ?? false;
        } catch (_) {
          try {
            granted =
                await (android as dynamic)?.requestNotificationsPermission()
                    as bool? ??
                false;
          } catch (_) {
            // Fall through
          }
        }
        if (!granted) {
          // Some OEMs or older Android versions may not support the runtime
          // request; re-check if enabled via system settings
          final nowEnabled = await android?.areNotificationsEnabled();
          return nowEnabled == true;
        }
        return true;
      }

      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted =
            await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
        return granted;
      }
    } catch (_) {
      // If anything goes wrong, fail open (app logic will still work),
      // and scheduling will simply no-op if not permitted.
    }
    return true;
  }

  Future<void> _handleNotificationTap(NotificationResponse response) async {
    // Handle rest timer notification actions and taps
    if (response.actionId == 'pause_rest') {
      try {
        final svc = GetIt.instance<RestTimerService>();
        svc.pauseTimer();
      } catch (_) {}
      return;
    }
    if (response.actionId == 'skip_rest') {
      try {
        final svc = GetIt.instance<RestTimerService>();
        svc.stopTimer();
        // Restore the ongoing workout chronometer so the tray keeps showing
        // workout duration even when rest is skipped from the shade.
        final start = _workoutStartTime ?? DateTime.now();
        await showWorkoutOngoing(
          startTime: start,
          currentExerciseName: _currentExerciseName,
        );
      } catch (_) {}
      return;
    }

    if (response.payload == 'rest_complete' ||
        response.payload == 'inactivity') {
      await navigateToActiveWorkout();
      return;
    }

    if (response.payload == 'rest_ongoing' ||
        response.payload == 'workout_ongoing') {
      await navigateToActiveWorkout();
      return;
    }

    if (response.payload == 'nutrition_checkin') {
      await navigateToNutritionStrategy();
      return;
    }

    if (response.payload == 'training_recap') {
      await navigateToProgress();
      return;
    }

    // AI proposal pending: 'proposal_pending' opens the inbox;
    // 'proposal_pending:<id>' opens that proposal's approval card directly.
    // 'proposal_log:<id>' opens an AUTO-applied log so the user can review/undo it.
    final payload = response.payload;
    if (payload != null &&
        (payload.startsWith('proposal_pending') ||
            payload.startsWith('proposal_log'))) {
      final sep = payload.indexOf(':');
      final id = sep >= 0 ? payload.substring(sep + 1).trim() : '';
      await navigateToProposal(id.isEmpty ? null : id);
      return;
    }
  }

  /// Open the AI-proposals surface from a notification tap. With an [id] it
  /// lands on that proposal's approval card; without one, the inbox.
  Future<void> navigateToProposal(String? id) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    // ignore: use_build_context_synchronously
    _pushOverHome(context, id == null ? '/proposals' : '/proposals/$id');
  }

  /// Open the Strategy screen so a check-in tap lands directly on the targets +
  /// "Review check-in" affordance.
  Future<void> navigateToNutritionStrategy() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    // ignore: use_build_context_synchronously
    _pushOverHome(context, '/nutrition/strategy');
  }

  /// Open the Progress tab so a training-recap tap lands on the weekly
  /// consistency card. Progress is a bottom-nav shell branch (not a top-level
  /// overlay), so a plain `go` switches to it with the nav bar intact — the
  /// _pushOverHome dance is only needed for chrome-less top-level routes.
  Future<void> navigateToProgress() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    // ignore: use_build_context_synchronously
    GoRouter.of(context).go('/progress');
  }

  /// Push a notification destination ON TOP of the home shell, so it always has
  /// a back route and the bottom nav underneath. These targets ('/proposals',
  /// '/proposals/:id', '/nutrition/strategy') are top-level routes on the root
  /// navigator: a plain `go` replaces the whole stack, stranding the user on a
  /// chrome-less screen with no back button and no nav (the reported dead-end).
  /// Landing '/' first guarantees a navigable base on both warm and cold starts.
  void _pushOverHome(BuildContext context, String location) {
    final router = GoRouter.of(context);
    router.go('/');
    router.push(location);
  }

  /// Handle a COLD-START notification tap. When the OS launches the app from a
  /// notification (the app was killed — e.g. the weekly check-in reminder),
  /// [onDidReceiveNotificationResponse] does NOT fire; the launching payload must
  /// be fetched via getNotificationAppLaunchDetails and dispatched once the
  /// router is mounted. Call this from the root widget after the first frame.
  Future<void> handleAppLaunchNotification() async {
    try {
      if (!_initialized) await init();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final response = details!.notificationResponse;
      if (response == null) return;
      // Cold start: the navigator may not be attached on the very first frame.
      // Wait briefly for navigatorKey.currentContext before dispatching.
      for (var i = 0; i < 25 && navigatorKey.currentContext == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await _handleNotificationTap(response);
    } catch (_) {
      // Best-effort: a failed launch dispatch must never crash startup.
    }
  }

  Future<void> navigateToActiveWorkout() async {
    try {
      // Get the latest active workout session
      final workoutRepository = GetIt.instance<WorkoutRepository>();
      final activeSession = await workoutRepository.getLatestActiveSession();

      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      if (activeSession != null) {
        // Navigate to the active workout with the session ID
        // Replace current route to avoid stacking when launching from shade.
        context.go(
          '/workout_session',
          extra: workoutRouteExtra(context, {
            'sessionId': activeSession.id,
            'initialName': activeSession.name,
          }),
        );
      } else {
        // No active session, navigate to workout home
        context.go('/workout_session', extra: workoutRouteExtra(context));
      }
    } catch (e) {
      // Fallback to workout home on error
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.go('/workout_session', extra: workoutRouteExtra(context));
      }
    }
  }

  Future<AudioPlayer?> _ensureBellPlayer() async {
    if (kIsWeb) return null;
    try {
      final existing = _bellPlayer;
      if (existing != null) {
        return existing;
      }
      final created = AudioPlayer();
      await created.setReleaseMode(ReleaseMode.stop);
      await created.setAudioContext(
        const AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.assistanceSonification,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: <AVAudioSessionOptions>[
              AVAudioSessionOptions.mixWithOthers,
            ],
          ),
        ),
      );
      _bellPlayer = created;
      return created;
    } catch (error, stackTrace) {
      dev.log(
        '[Notifications] Failed to init rest bell player',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  Future<void> _prepareIosRestBellIfNeeded({
    Future<Directory> Function()? libraryDirectoryProvider,
    Future<ByteData> Function(String asset)? assetLoader,
    bool force = false,
  }) async {
    if (kIsWeb) return;
    if (!force) {
      if (!Platform.isIOS || _iosRestBellReady) {
        return;
      }
    } else if (_iosRestBellReady) {
      return;
    }

    try {
      final Directory libraryDir =
          await (libraryDirectoryProvider ?? getLibraryDirectory)();
      final Directory soundsDir = Directory('${libraryDir.path}/Sounds');
      if (!await soundsDir.exists()) {
        await soundsDir.create(recursive: true);
      }

      final File bellFile = File('${soundsDir.path}/$_restBellIosSound');
      if (await bellFile.exists()) {
        _iosRestBellReady = true;
        return;
      }

      final ByteData data = await (assetLoader ?? rootBundle.load)(
        'assets/audio/rest_bell.wav',
      );
      await bellFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      _iosRestBellReady = true;
    } catch (error, stackTrace) {
      dev.log(
        '[Notifications] Failed to stage iOS rest bell sound',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _playRestBell() async {
    try {
      final player = await _ensureBellPlayer();
      if (player == null) return;
      await player.stop();
      await player.play(AssetSource('audio/rest_bell.wav'));
    } catch (error, stackTrace) {
      dev.log(
        '[Notifications] Failed to play rest bell',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> showRestComplete({
    String? exerciseName,
    bool isNextSet = false,
    bool skipForegroundBell = false,
  }) async {
    await init();

    if (kIsWeb) {
      // Skip showing notifications on web; plugin not supported.
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final AppLifecycleState? lifecycleState =
        WidgetsBinding.instance.lifecycleState;
    final bool appInForeground = lifecycleState == AppLifecycleState.resumed;

    final RestNotificationPresentation presentation =
        computeRestNotificationPresentation(
          appInForeground: appInForeground,
          skipForegroundBell: skipForegroundBell,
        );

    final NotificationDetails details = buildRestCompletionDetails(
      playSound: presentation.playSound,
      presentAlert: presentation.presentAlert,
    );

    const String title = '💪 Rest complete';
    final String body;
    if (exerciseName == null || exerciseName.isEmpty) {
      body = 'Time to get moving again! 🔥';
    } else if (isNextSet) {
      body = 'Next set: $exerciseName 🔁';
    } else {
      body = 'Next exercise: $exerciseName ▶️';
    }

    await _plugin.show(1001, title, body, details, payload: 'rest_complete');

    if (presentation.playForegroundBell) {
      await _playRestBell();
    }
  }

  Future<void> updateRestLiveActivity(
    int seconds, {
    String? exerciseName,
    bool isPaused = false,
  }) async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      await _restLiveActivityChannel
          .invokeMethod('startOrUpdate', <String, dynamic>{
            'remainingSeconds': seconds,
            'exerciseName': exerciseName,
            'isPaused': isPaused,
          });
    } catch (error, stackTrace) {
      dev.log(
        '[Notifications] Failed to update Live Activity',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> endRestLiveActivity() async {
    if (_initialized && !kIsWeb && Platform.isIOS) {
      try {
        await _restLiveActivityChannel.invokeMethod('end');
      } catch (error, stackTrace) {
        dev.log(
          '[Notifications] Failed to end Live Activity',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<bool> isRestCompleteNotificationPending() async {
    await init();

    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.id == 1001) {
          return true;
        }
      }
    } catch (error, stackTrace) {
      dev.log(
        '[Notifications] Failed to query pending rest complete notification',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return false;
  }

  /// Show/update an ongoing countdown notification for the active rest timer.
  /// Android-only: uses chronometer countdown in the system tray for accuracy
  /// without requiring exact alarm permission. Call again with the same ID to
  /// update the countdown (e.g., when time is adjusted). Call
  /// [cancelRestOngoing] to remove it.
  Future<void> showRestOngoing(int seconds, {String? exerciseName}) async {
    final int gen = ++_ongoingNotificationGeneration;
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    if (gen != _ongoingNotificationGeneration) return;

    final safeSeconds = seconds < 0 ? 0 : seconds;
    final endEpochMs = DateTime.now()
        .add(Duration(seconds: safeSeconds))
        .millisecondsSinceEpoch;

    // If no exercise context is provided (e.g., global timer), clear any
    // previous name to avoid stale titles from earlier sessions.
    _currentExerciseName = (exerciseName != null && exerciseName.isNotEmpty)
        ? exerciseName
        : null;

    final bool restActive = safeSeconds > 0;
    final whenForWorkout =
        (_workoutStartTime ?? DateTime.now()).millisecondsSinceEpoch;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'workout_ongoing_channel',
        'Workout (Ongoing)',
        channelDescription: 'Ongoing countdown for rest timer and workout',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: true,
        usesChronometer: true,
        chronometerCountDown: restActive,
        when: restActive ? endEpochMs : whenForWorkout,
        actions: restActive
            ? const <AndroidNotificationAction>[
                AndroidNotificationAction(
                  'skip_rest',
                  'Skip rest timer',
                  showsUserInterface: true,
                ),
              ]
            : null,
      ),
    );

    final title = restActive
        ? _formatRestForTitle(safeSeconds)
        : (_currentExerciseName?.isNotEmpty == true
              ? _currentExerciseName!
              : 'Workout in progress');
    final workout = _formatWorkoutDurationForBody();
    final body = _currentExerciseName?.isNotEmpty == true
        ? '${_currentExerciseName!} • $workout'
        : workout;

    await _plugin.show(
      1004, // single ongoing notification id for workout/rest
      title,
      body,
      details,
      payload: 'rest_ongoing',
    );
  }

  Future<void> cancelRestOngoing() async {
    _ongoingNotificationGeneration++;
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(1004);
  }

  Future<void> scheduleRestComplete(
    int seconds, {
    String? exerciseName,
    bool isNextSet = false,
  }) async {
    await init();

    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Cancel any existing scheduled notification for rest completion
    await cancelRestComplete();

    final NotificationDetails details = buildRestCompletionDetails(
      playSound: true,
    );

    const String title = '💪 Rest complete';
    final String body;
    if (exerciseName == null || exerciseName.isEmpty) {
      body = 'Time to get moving again! 🔥';
    } else if (isNextSet) {
      body = 'Next set: $exerciseName 🔁';
    } else {
      body = 'Next exercise: $exerciseName ▶️';
    }

    final scheduledDate = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));

    // Pick a schedule mode that doesn't silently fail on Android 12+.
    final AndroidScheduleMode mode = await _chooseAndroidScheduleMode(
      preferExact: false,
    );
    dev.log(
      '[Notifications] scheduleRestComplete: in $seconds s at '
      '${scheduledDate.toIso8601String()} mode=$mode',
    );

    await _plugin.zonedSchedule(
      1001,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'rest_complete',
    );
  }

  Future<void> cancelRestComplete() async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    dev.log('[Notifications] cancelRestComplete: id=1001');
    await _plugin.cancel(1001);
  }

  Future<void> scheduleInactivityReminder(int seconds) async {
    await init();

    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'inactivity_channel',
        'Inactivity Reminder',
        channelDescription: 'Notifications when workout remains inactive',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    );

    final scheduledDate = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));

    final AndroidScheduleMode mode = await _chooseAndroidScheduleMode(
      preferExact: false,
    );
    dev.log(
      '[Notifications] scheduleInactivityReminder: in $seconds s at '
      '${scheduledDate.toIso8601String()} mode=$mode',
    );
    final rawMinutes = seconds ~/ 60;
    final minutes = rawMinutes < 1 ? 1 : (rawMinutes > 120 ? 120 : rawMinutes);
    final timeLabel = minutes == 1 ? '1 minute' : '$minutes minutes';

    await _plugin.zonedSchedule(
      1002,
      'Still there?',
      'You\'ve been inactive for $timeLabel. Let\'s get moving!',
      scheduledDate,
      details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'inactivity',
    );
  }

  Future<AndroidScheduleMode> _chooseAndroidScheduleMode({
    required bool preferExact,
  }) async {
    if (kIsWeb) return AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      if (Platform.isAndroid) {
        // Ensure notification permission is granted/enabled first.
        await ensurePermissionsForWorkout();

        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        // We avoid requesting exact alarms to prevent the OS permission prompt.
        // If the app already has exact alarm permission and preferExact is true,
        // we use it; otherwise fall back to inexact to avoid extra friction.
        if (preferExact) {
          bool allowed = false;
          try {
            allowed =
                await (android as dynamic)?.areExactAlarmsAllowed() as bool? ??
                false;
          } catch (_) {}
          if (allowed) return AndroidScheduleMode.exactAllowWhileIdle;
        }
        return AndroidScheduleMode.inexactAllowWhileIdle;
      }
    } catch (_) {
      // ignore
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> cancelInactivityReminder() async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(1002);
  }

  /// Arm the repeating weekly nutrition check-in reminder at [weekday]
  /// ([DateTime.monday]…[DateTime.sunday]) and [hour]:[minute]. Idempotent —
  /// scheduling again with the same id overwrites the previous one, so callers
  /// can re-sync freely. Uses inexact, while-idle delivery (no exact-alarm
  /// prompt) and a single repeat via [DateTimeComponents.dayOfWeekAndTime], so
  /// it survives reboots and never trips the iOS 64-pending cap.
  Future<void> scheduleWeeklyCheckIn({
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Requesting permission here (idempotent) means an opt-in from Settings or
    // the Strategy primer lands the OS prompt before the schedule is committed.
    await ensurePermissionsForWorkout();

    final next = nextWeeklyInstance(
      from: DateTime.now(),
      weekday: weekday,
      hour: hour,
      minute: minute,
    );
    final scheduledDate = tz.TZDateTime(
      tz.local,
      next.year,
      next.month,
      next.day,
      next.hour,
      next.minute,
    );

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _checkInChannelId,
        _checkInChannelName,
        channelDescription: _checkInChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        // Passive: a soft nudge that won't break through Focus — never nags.
        interruptionLevel: InterruptionLevel.passive,
      ),
    );

    final AndroidScheduleMode mode = await _chooseAndroidScheduleMode(
      preferExact: false,
    );
    dev.log(
      '[Notifications] scheduleWeeklyCheckIn: weekday=$weekday '
      '$hour:$minute next=${scheduledDate.toIso8601String()} mode=$mode',
    );

    await _plugin.zonedSchedule(
      kWeeklyCheckInId,
      'Your weekly check-in is ready',
      'See how this week went and get next week\'s targets.',
      scheduledDate,
      details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: 'nutrition_checkin',
    );
  }

  Future<void> cancelWeeklyCheckIn() async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(kWeeklyCheckInId);
  }

  /// Whether the repeating weekly check-in reminder is currently scheduled.
  Future<bool> isWeeklyCheckInScheduled() async {
    await init();
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.any((r) => r.id == kWeeklyCheckInId);
    } catch (_) {
      return false;
    }
  }

  /// Arm the repeating weekly training recap reminder at [weekday]
  /// ([DateTime.monday]…[DateTime.sunday]) and [hour]:[minute]. Mirrors
  /// [scheduleWeeklyCheckIn] line-for-line — idempotent (same id overwrites),
  /// inexact/while-idle delivery (no exact-alarm prompt), passive interruption,
  /// and a single repeat via [DateTimeComponents.dayOfWeekAndTime] so it survives
  /// reboots and never trips the iOS 64-pending cap. Deep-links to the Progress
  /// tab so the tap lands on the weekly consistency card.
  Future<void> scheduleWeeklyTrainingRecap({
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Requesting permission here (idempotent) means an opt-in from Settings
    // lands the OS prompt before the schedule is committed.
    await ensurePermissionsForWorkout();

    final next = nextWeeklyInstance(
      from: DateTime.now(),
      weekday: weekday,
      hour: hour,
      minute: minute,
    );
    final scheduledDate = tz.TZDateTime(
      tz.local,
      next.year,
      next.month,
      next.day,
      next.hour,
      next.minute,
    );

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _trainingRecapChannelId,
        _trainingRecapChannelName,
        channelDescription: _trainingRecapChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        // Passive: a soft nudge that won't break through Focus — never nags.
        interruptionLevel: InterruptionLevel.passive,
      ),
    );

    final AndroidScheduleMode mode = await _chooseAndroidScheduleMode(
      preferExact: false,
    );
    dev.log(
      '[Notifications] scheduleWeeklyTrainingRecap: weekday=$weekday '
      '$hour:$minute next=${scheduledDate.toIso8601String()} mode=$mode',
    );

    await _plugin.zonedSchedule(
      kWeeklyTrainingRecapId,
      'Your training week, wrapped',
      'See what you lifted this week and what\'s coming next.',
      scheduledDate,
      details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: 'training_recap',
    );
  }

  Future<void> cancelWeeklyTrainingRecap() async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(kWeeklyTrainingRecapId);
  }

  /// Whether the repeating weekly training recap reminder is currently scheduled.
  Future<bool> isWeeklyTrainingRecapScheduled() async {
    await init();
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.any((r) => r.id == kWeeklyTrainingRecapId);
    } catch (_) {
      return false;
    }
  }

  /// Notify that a connected AI auto-logged a meal/workout, deep-linking to the
  /// proposal so the user can review or UNDO it. A distinct notification id per
  /// proposal (derived from its id) so multiple logs don't overwrite each other.
  Future<void> showAutoLoggedProposal({
    required String id,
    required bool isFood,
    required String body,
  }) async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _aiLogChannelId,
        _aiLogChannelName,
        channelDescription: _aiLogChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        // Passive: informational, never an alarm — the user can undo at leisure.
        interruptionLevel: InterruptionLevel.passive,
      ),
    );

    final String title = isFood
        ? '🍽 Meal logged by your assistant'
        : '🏋 Workout logged by your assistant';
    // Stable, full 31-bit id from the proposal UUID. (A prior `% 1000` compressed
    // into 1000 buckets, so distinct proposals could collide and overwrite each
    // other's notification while the poll watermark still advanced past them.)
    final int notifId = id.hashCode & 0x7fffffff;

    await _plugin.show(
      notifId,
      title,
      body,
      details,
      payload: 'proposal_log:$id',
    );
  }

  /// Show a small, user-visible error notification when background sync fails.
  /// Web platforms are ignored; mobile platforms use a lightweight channel.
  Future<void> showSyncError(String message) async {
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sync_channel',
        'Background Sync',
        channelDescription: 'Notifications for workout data sync status',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    );

    await _plugin.show(
      2001,
      'Sync failed',
      message,
      details,
      payload: 'sync_error',
    );
  }

  // --- Workout ongoing persistent notification (Android only) ---
  Future<void> showWorkoutOngoing({
    required DateTime startTime,
    String? currentExerciseName,
  }) async {
    final int gen = ++_ongoingNotificationGeneration;
    await init();
    if (kIsWeb || !Platform.isAndroid) return;
    if (gen != _ongoingNotificationGeneration) return;

    _workoutStartTime = startTime;
    // If no exercise provided, clear any previous value to avoid stale titles
    _currentExerciseName =
        (currentExerciseName != null && currentExerciseName.isNotEmpty)
        ? currentExerciseName
        : null;

    final when = startTime.millisecondsSinceEpoch;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'workout_ongoing_channel',
        'Workout (Ongoing)',
        channelDescription: 'Shows the current exercise and workout duration',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: true,
        usesChronometer: true,
        // Count up from the workout start time
        chronometerCountDown: false,
        when: when,
      ),
    );

    final title = _currentExerciseName?.isNotEmpty == true
        ? _currentExerciseName!
        : 'Workout in progress';
    final body = _formatWorkoutDurationForBody();

    await _plugin.show(
      1004, // same ongoing id
      title,
      body,
      details,
      payload: 'workout_ongoing',
    );
  }

  Future<void> cancelWorkoutOngoing() async {
    _ongoingNotificationGeneration++;
    await init();
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _plugin.cancel(1004);
    // Clear state so a new workout starts clean without stale titles
    _currentExerciseName = null;
    _workoutStartTime = null;
  }

  String _formatRestForTitle(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _formatWorkoutDurationForBody() {
    final start = _workoutStartTime;
    if (start == null) return '';
    final secs = DateTime.now().difference(start).inSeconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return 'Workout $mm:$ss';
  }
}

@visibleForTesting
NotificationDetails buildRestCompletionDetails({
  required bool playSound,
  bool presentAlert = true,
}) {
  final String channelId = playSound
      ? _restCompleteChannelId
      : _restCompleteSilentChannelId;
  final String channelName = playSound
      ? _restCompleteChannelName
      : _restCompleteSilentChannelName;
  final String channelDescription = playSound
      ? _restCompleteChannelDescription
      : _restCompleteSilentChannelDescription;

  return NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: playSound,
      sound: playSound
          ? const RawResourceAndroidNotificationSound(_restBellAndroidSound)
          : null,
      audioAttributesUsage: playSound
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: presentAlert,
      presentBadge: false,
      presentSound: playSound,
      sound: playSound ? _restBellIosSound : null,
      interruptionLevel: playSound
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.passive,
    ),
  );
}

class RestNotificationPresentation {
  const RestNotificationPresentation({
    required this.playSound,
    required this.presentAlert,
    required this.playForegroundBell,
  });

  final bool playSound;
  final bool presentAlert;
  final bool playForegroundBell;
}

RestNotificationPresentation computeRestNotificationPresentation({
  required bool appInForeground,
  required bool skipForegroundBell,
}) {
  final bool playForegroundBell = !skipForegroundBell && appInForeground;
  final bool playSound = !skipForegroundBell && !appInForeground;
  final bool presentAlert = !appInForeground;
  return RestNotificationPresentation(
    playSound: playSound,
    presentAlert: presentAlert,
    playForegroundBell: playForegroundBell,
  );
}

@visibleForTesting
extension NotificationServiceTestHelpers on NotificationService {
  Future<void> debugPrepareIosRestBellSound({
    Future<Directory> Function()? libraryDirectoryProvider,
    Future<ByteData> Function(String asset)? assetLoader,
    bool force = false,
  }) {
    return _prepareIosRestBellIfNeeded(
      libraryDirectoryProvider: libraryDirectoryProvider,
      assetLoader: assetLoader,
      force: force,
    );
  }

  void resetIosRestBellCacheForTest() {
    _iosRestBellReady = false;
  }
}
