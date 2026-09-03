import '../../../domain/models/daily_recovery_snapshot.dart';
import '../../../domain/usecases/recovery_band_copy.dart';

String bandLabel(RecoveryReadinessBand? band) {
  return switch (band) {
    RecoveryReadinessBand.high => 'Excellent',
    RecoveryReadinessBand.moderate => 'Fair',
    RecoveryReadinessBand.low => 'Lower',
    null => 'Building',
  };
}

/// The four-band label (Charged / Ready / Steady / Recharge). Falls back to the
/// legacy three-band label when only the legacy band is populated, and to
/// "Building" while calibrating or with no band — so the surface reads exactly
/// as today when recovery data is absent.
String flowBandLabel(DailyRecoverySnapshot? snapshot) {
  if (snapshot == null) return 'Building';
  if (snapshot.isCalibrating && snapshot.flowBand == null) return 'Building';
  final flowBand = snapshot.flowBand;
  if (flowBand != null) return flowBand.displayLabel;
  return bandLabel(snapshot.band);
}

/// A short, ring-side headline for the recovery hero — band, confidence and
/// calibration aware, kind and non-medical (delegates to [RecoveryBandCopy]).
String coachHeadline(DailyRecoverySnapshot? snapshot) {
  return RecoveryBandCopy.headline(snapshot);
}

/// The full coaching paragraph — band, confidence and calibration aware, with a
/// kind anomaly note appended when markers look off baseline.
String coachCopy(DailyRecoverySnapshot? snapshot) {
  final guidance = RecoveryBandCopy.guidance(snapshot);
  final anomaly = RecoveryBandCopy.anomalyNote(snapshot);
  if (anomaly == null) return guidance;
  return '$guidance $anomaly';
}

String weightStatus(double? weeklyDelta) {
  if (weeklyDelta == null) return 'Waiting for more measurements';
  if (weeklyDelta.abs() < 0.1) return 'Stable';
  return weeklyDelta > 0 ? 'Increasing' : 'Dropping';
}

String bmiStatus(double? bmi) {
  if (bmi == null) return 'No composition data';
  if (bmi < 18.5) return 'Lean';
  if (bmi < 25) return 'Balanced';
  if (bmi < 30) return 'Above target';
  return 'High';
}
