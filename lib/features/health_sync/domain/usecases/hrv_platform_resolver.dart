import 'package:flutter/foundation.dart';

import '../models/daily_recovery_snapshot.dart';
import 'hrv_platform_io.dart'
    if (dart.library.html) 'hrv_platform_web.dart'
    as platform;

/// Default, platform-correct HRV kind for the running device.
///
/// iOS (HealthKit) exposes HRV as SDNN; Android (Health Connect) exposes it as
/// RMSSD. The two metrics are not numerically interchangeable, so the recovery
/// model must prefer the platform-native kind and never mix them into one
/// baseline. Returns null on web / unknown platforms where neither is canonical.
class PlatformHrvResolver {
  PlatformHrvResolver._();

  static HrvKind? kind() {
    if (kIsWeb) return null;
    return platform.platformHrvKind();
  }
}
