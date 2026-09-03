import 'package:flutter/foundation.dart';

class PreferencesService {
  factory PreferencesService() => _instance;
  PreferencesService._();
  static final _instance = PreferencesService._();

  final weeklyWorkoutGoalListenable = ValueNotifier<int>(3);
  final showExternalWorkoutsInDayListenable = ValueNotifier<bool>(false);
  final Map<String, Object?> _values = {};

  Future<void> init() async {}
  Future<int> getWeeklyWorkoutGoal() async => weeklyWorkoutGoalListenable.value;
  Future<String> getWeightUnit() async => (_values['weightUnit'] as String?) ?? 'kg';
  Future<String?> getNutritionWeighInPromptDismissedDay() async =>
      _values['weighInDismissed'] as String?;
  Future<void> setNutritionWeighInPromptDismissedDay(String? value) async =>
      _values['weighInDismissed'] = value;
  Future<bool> getAiCaptureConsent() async =>
      (_values['aiCaptureConsent'] as bool?) ?? false;
  Future<void> setAiCaptureConsent(bool value) async =>
      _values['aiCaptureConsent'] = value;
  Future<bool> getAddFoodContextMode() async =>
      (_values['addFoodContextMode'] as bool?) ?? false;
  Future<void> setAddFoodContextMode(bool value) async =>
      _values['addFoodContextMode'] = value;
  bool get hapticsEnabled => false;
  bool get showExternalWorkoutsInDay => false;
  bool get seenHealthConnectPrimer => true;
  bool get onboardingFirstWinSeen => true;
  bool get shouldAutoStartRestTimer => false;
  bool get suggestNextSetTargets => true;
  int get inactivityReminderMinutes => 60;
  Future<bool> getCoachIntroSeen() async => true;
  Future<void> setCoachIntroSeen(bool value) async {}
  Future<void> incrementApprovedProposalsCount() async {}
  Future<Map<String, String>> getWorkoutWritebackMappings() async => const {};
  Future<bool> getCoachExplainsEnabled() async => false;
  Future<void> setCoachExplainsEnabled(bool value) async {}
  Future<void> setBehavioralMomentumEnabled(bool value) async {}
  Future<void> setSeenHealthConnectPrimer(bool value) async {}
  Future<bool> getSeenMealScanCameraPrimer() async => true;
  Future<void> setSeenMealScanCameraPrimer(bool value) async {}
  Future<String?> getRawString(String key) async => _values[key] as String?;
  Future<void> setRawString(String key, String? value) async => _values[key] = value;
  Future<bool> getWatchHeartRateRecordingEnabled() async => false;
  Future<bool> getOnboardingV2SeenCoachmarkLogFirstSet() async => true;
  Future<void> setOnboardingV2SeenCoachmarkLogFirstSet(bool value) async {}
  Future<bool> getSeenSupersetHint() async => true;
  Future<void> setSeenSupersetHint(bool value) async {}
  Future<bool> getOnboardingV2SeenNotificationPrimer() async => true;
  Future<void> setOnboardingV2SeenNotificationPrimer(bool value) async {}
  Future<void> setOnboardingFirstWinSeen(bool value) async {}
  Future<bool> getSupersetAutoAdvance() async => false;
  Future<void> setExerciseRestTimer(String exerciseName, int seconds) async {}
}
