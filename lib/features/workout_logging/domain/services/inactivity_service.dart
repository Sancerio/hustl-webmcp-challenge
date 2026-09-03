import 'dart:async';

import '../../../../core/services/notification_service.dart';
import '../../../../core/services/preferences_service.dart';

/// Service that schedules a reminder if the workout remains inactive
class InactivityService {
  final NotificationService _notificationService;
  final PreferencesService _preferencesService;
  Timer? _timer;

  InactivityService({
    required NotificationService notificationService,
    required PreferencesService preferencesService,
  }) : _notificationService = notificationService,
       _preferencesService = preferencesService;

  /// Start tracking inactivity
  void start() {
    _schedule();
  }

  /// Record user activity and restart the inactivity timer
  void recordActivity() {
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _notificationService.cancelInactivityReminder();
    final inactivityMinutes = _preferencesService.inactivityReminderMinutes;
    final inactivitySeconds = (inactivityMinutes * 60).clamp(60, 3600);
    _timer = Timer(Duration(seconds: inactivitySeconds), () {
      // Once timer fires, allow future reminders after user resumes
      _timer = null;
    });
    _notificationService.scheduleInactivityReminder(inactivitySeconds);
  }

  /// Stop tracking and cancel any scheduled reminders
  void stop() {
    _timer?.cancel();
    _timer = null;
    _notificationService.cancelInactivityReminder();
  }

  void dispose() => stop();
}
