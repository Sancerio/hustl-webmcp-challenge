import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Set via --dart-define=HUSTL_API_BASE_URL=https://offline.invalid
  static const String baseUrl = String.fromEnvironment(
    'HUSTL_API_BASE_URL',
    defaultValue: 'http://localhost:3001', // sensible local default
  );

  /// Auth endpoints on web should be same-origin in production so Vercel can
  /// proxy `/api/*` to the backend and cookies remain first-party.
  ///
  /// Local development still uses [baseUrl] to talk to a separate backend.
  static String get authBaseUrl {
    if (!kIsWeb) return baseUrl;
    final host = Uri.base.host;
    final isLocalhost =
        host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';
    if (isLocalhost) return baseUrl;
    return Uri.base.origin;
  }

  // iOS Google OAuth client ID (for native sign-in)
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  // Web OAuth client ID (used as serverClientId for native sign-in)
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  /// Local/internal builds may opt into the backend's debug-only exercise
  /// generation endpoints. Production builds omit this define, which also
  /// removes the generation controls from the UI.
  static const String exerciseGenerationDebugToken = String.fromEnvironment(
    'HUSTL_EXERCISE_GENERATION_DEBUG_TOKEN',
    defaultValue: '',
  );

  static bool get debugExerciseGenerationEnabled =>
      exerciseGenerationDebugToken.isNotEmpty;
}
