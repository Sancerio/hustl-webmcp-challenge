import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:get_it/get_it.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/workout_logging/domain/models/workout_session.dart';
import '../../features/workout_logging/domain/repositories/workout_repository.dart';
import 'preferences_service.dart';

/// Coordinates data shared with the native home-screen widgets.
class WorkoutWidgetService {
  WorkoutWidgetService({
    WorkoutRepository? workoutRepository,
    PreferencesService? preferencesService,
  }) : _workoutRepository =
           workoutRepository ?? GetIt.instance<WorkoutRepository>(),
       _preferencesService =
           preferencesService ?? GetIt.instance<PreferencesService>();

  static const String androidProviderName =
      'com.hustl.app.widget.WorkoutsSummaryWidgetProvider';
  static const String androidSmallProviderName =
      'com.hustl.app.widget.WorkoutsSummaryWidgetSmallProvider';
  static const String iosWidgetKind = 'WorkoutsSummaryWidget';

  static const String titleKey = 'workout_widget_title';
  static const String goalKey = 'workout_widget_goal';
  static const String currentWeekCountKey = 'workout_widget_current_week_count';
  static const String goalMetWeeksKey = 'workout_widget_goal_met_weeks';
  static const String goalWindowWeeksKey = 'workout_widget_goal_window_weeks';
  static const String weekLabelKey = 'workout_widget_week_label';
  static const String lastUpdatedKey = 'workout_widget_last_updated';
  static const String weeklyHistoryKey = 'workout_widget_weekly_history';

  static const int historyWindowWeeks = 9;
  static const Duration _historyWindowSpan = Duration(
    days: 7 * (historyWindowWeeks - 1),
  );

  final WorkoutRepository _workoutRepository;
  final PreferencesService _preferencesService;

  /// Push the latest workout metrics to the platform widgets and trigger a refresh.
  Future<void> updateWorkoutsPerWeekWidget({DateTime? now}) async {
    if (!_isHomeWidgetSupported) {
      return;
    }

    final DateTime reference = now ?? DateTime.now();
    final DateTime weekStart = _startOfIsoWeek(reference);
    final DateTime oldestWeekStart = weekStart.subtract(_historyWindowSpan);
    final DateTime exclusiveEnd = weekStart.add(const Duration(days: 7));

    final List<WorkoutSession> sessions = await _workoutRepository
        .getWorkoutSessions(
          startDate: oldestWeekStart.subtract(const Duration(seconds: 1)),
          endDate: exclusiveEnd,
        );

    final Map<String, int> weeklyCounts = <String, int>{};
    for (final WorkoutSession session in sessions) {
      if (!session.isCompleted) continue;
      final DateTime sessionWeekStart = _startOfIsoWeek(session.startTime);
      final String key = _isoWeekKey(sessionWeekStart);
      weeklyCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }

    final int weeklyGoal = await _preferencesService.getWeeklyWorkoutGoal();
    final List<DateTime> orderedWeeks = List<DateTime>.generate(
      historyWindowWeeks,
      (int index) => weekStart.subtract(
        Duration(days: 7 * (historyWindowWeeks - 1 - index)),
      ),
    );

    final List<Map<String, dynamic>> weeklyHistoryPayload = orderedWeeks
        .map(
          (DateTime start) => <String, dynamic>{
            'weekStart': start.toUtc().toIso8601String(),
            'count': weeklyCounts[_isoWeekKey(start)] ?? 0,
          },
        )
        .toList();

    int goalMetWeeks = 0;
    for (final DateTime start in orderedWeeks) {
      final String key = _isoWeekKey(start);
      final int count = weeklyCounts[key] ?? 0;
      if (count >= weeklyGoal && weeklyGoal > 0) {
        goalMetWeeks++;
      }
    }

    final int currentWeekCount = weeklyCounts[_isoWeekKey(weekStart)] ?? 0;

    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>(titleKey, 'Workouts Per Week'),
        HomeWidget.saveWidgetData<int>(goalKey, weeklyGoal),
        HomeWidget.saveWidgetData<int>(currentWeekCountKey, currentWeekCount),
        HomeWidget.saveWidgetData<int>(goalMetWeeksKey, goalMetWeeks),
        HomeWidget.saveWidgetData<int>(goalWindowWeeksKey, historyWindowWeeks),
        HomeWidget.saveWidgetData<String>(
          weekLabelKey,
          _formatWeekRangeLabel(weekStart, reference),
        ),
        HomeWidget.saveWidgetData<String>(
          lastUpdatedKey,
          reference.toUtc().toIso8601String(),
        ),
        HomeWidget.saveWidgetData<String>(
          weeklyHistoryKey,
          jsonEncode(weeklyHistoryPayload),
        ),
      ]);

      await Future.wait([
        HomeWidget.updateWidget(
          qualifiedAndroidName: androidProviderName,
          iOSName: iosWidgetKind,
          name: iosWidgetKind,
        ),
        HomeWidget.updateWidget(
          qualifiedAndroidName: androidSmallProviderName,
          iOSName: iosWidgetKind,
          name: iosWidgetKind,
        ),
      ]);
    } on MissingPluginException catch (error, stackTrace) {
      dev.log(
        'HomeWidget plugin unavailable; skipping widget refresh.',
        name: 'WorkoutWidgetService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  DateTime _startOfIsoWeek(DateTime date) {
    final DateTime truncated = DateTime(date.year, date.month, date.day);
    final int isoWeekday = truncated.weekday == DateTime.sunday
        ? 7
        : truncated.weekday; // ISO Monday=1, Sunday=7
    return truncated.subtract(Duration(days: isoWeekday - 1));
  }

  String _isoWeekKey(DateTime date) {
    final DateTime start = _startOfIsoWeek(date);
    final int week = _isoWeekNumber(start);
    return '${start.year}-W${week.toString().padLeft(2, '0')}';
  }

  int _isoWeekNumber(DateTime date) {
    final DateTime thursday = date.add(
      Duration(days: 3 - ((date.weekday + 6) % 7)),
    );
    final DateTime firstThursday = DateTime(thursday.year, 1, 4);
    final DateTime firstWeekStart = firstThursday.subtract(
      Duration(days: (firstThursday.weekday + 6) % 7),
    );
    return 1 + (thursday.difference(firstWeekStart).inDays ~/ 7);
  }

  String _formatWeekRangeLabel(DateTime start, DateTime now) {
    final DateTime end = start.add(const Duration(days: 6));
    final DateFormat formatter = DateFormat.MMMd();
    final String startLabel = formatter.format(start);
    final String endLabel = formatter.format(end);
    final bool isCurrentWeek =
        now.isAfter(start) && now.isBefore(end.add(const Duration(days: 1)));
    final String suffix = isCurrentWeek ? ' | This Week' : '';
    if (start.year == end.year) {
      return '$startLabel - $endLabel$suffix';
    }
    final DateFormat fullFormatter = DateFormat.yMMMd();
    return '${fullFormatter.format(start)} - ${fullFormatter.format(end)}$suffix';
  }

  bool get _isHomeWidgetSupported {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
