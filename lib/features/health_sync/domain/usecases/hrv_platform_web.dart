import '../models/daily_recovery_snapshot.dart';

/// On web neither SDNN nor RMSSD is canonical; HRV is not read.
HrvKind? platformHrvKind() => null;
