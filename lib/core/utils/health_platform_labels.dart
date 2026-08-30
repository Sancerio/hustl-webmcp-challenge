import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// User-facing labels for the underlying health integration.
///
/// We intentionally keep these in a single place because multiple features
/// reference them (Health Insights, Nutrition, Settings).
String healthPlatformLabel({TargetPlatform? platform}) {
  if (kIsWeb) return 'Health';
  final p = platform ?? defaultTargetPlatform;
  return switch (p) {
    TargetPlatform.android => 'Health Connect',
    TargetPlatform.iOS => 'Apple Health',
    _ => 'Health',
  };
}
