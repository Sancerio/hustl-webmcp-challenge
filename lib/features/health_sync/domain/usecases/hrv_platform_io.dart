import 'dart:io' show Platform;

import '../models/daily_recovery_snapshot.dart';

/// Native platform HRV kind: SDNN on iOS, RMSSD on Android.
HrvKind? platformHrvKind() {
  if (Platform.isIOS) return HrvKind.sdnn;
  if (Platform.isAndroid) return HrvKind.rmssd;
  return null;
}
