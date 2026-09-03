import 'preferences_service.dart';

class AnalyticsService {
  AnalyticsService({PreferencesService? preferences, Object? sink});

  void logEvent(String name, {Map<String, Object?>? props}) {}
}
