import '../../features/health_sync/domain/models/daily_recovery_snapshot.dart';
import '../../features/health_sync/domain/usecases/recovery_band_copy.dart';
import '../../features/health_sync/presentation/widgets/dashboard/health_dashboard_copy.dart';
import '../../features/health_sync/presentation/widgets/dashboard/recovery_coach.dart';

/// Builds the PII-free, PHI-SAFE `RecoveryFacts` payload the shared
/// "explain any number" endpoint (`recovery` domain) expects, from a
/// [DailyRecoverySnapshot].
///
/// ┌───────────────────────────────────────────────────────────────────────┐
/// │ PHI IS THE HEADLINE CONSTRAINT.                                         │
/// │                                                                         │
/// │ The snapshot co-locates SAFE derived scores with RAW BIOMETRICS (HRV   │
/// │ ms, resting HR bpm, respiratory rate, blood oxygen, skin temperature,  │
/// │ raw sleep-stage minutes, steps, active energy, raw training load).     │
/// │ Those RAW biometrics must NEVER leave the device for the LLM.          │
/// │                                                                         │
/// │ This mapper is a STRICT WHITELIST: it reads ONLY the derived,          │
/// │ PII-safe fields below + the vetted copy strings. It NEVER reads        │
/// │ snapshot.hrvValue / restingHeartRateBpm / respiratoryRate /            │
/// │ bloodOxygenPercent / temperatureCelsius / *SleepMinutes / steps /      │
/// │ activeEnergyKilocalories / trainingLoad / acuteLoad7 / chronicLoad42.  │
/// │ Adding a raw field here would be a PHI leak — keep this map's keys      │
/// │ EXACTLY the backend whitelist (enforced by a test).                    │
/// └───────────────────────────────────────────────────────────────────────┘
///
/// Numbers are rounded HERE (the contract says the model receives values, never
/// formulas), and only derived display signals + human-reviewed copy travel.
Map<String, dynamic> recoveryExplainFacts(DailyRecoverySnapshot snapshot) {
  // The readiness band LABEL string (e.g. "Ready") — never a raw signal.
  final band = snapshot.flowBand;
  // The "why it matters" clause is only meaningful for a settled band; null
  // while calibrating (gate blocks that anyway).
  final whyItMatters = band != null ? recoveryWhyItMatters(band) : null;

  return {
    // Derived 0-100 scores (rounded). Null stays null (calibrating user).
    'readinessScore': snapshot.readinessScore?.round(),
    'recoveryScore': snapshot.recoveryScore?.round(),
    // Enum LABEL strings, never the raw enum or a raw signal.
    'band': flowBandLabel(snapshot),
    'confidence': RecoveryBandCopy.confidenceLabel(snapshot.confidence),
    // Derived 0-21 strain.
    'strainScore': snapshot.strainScore,
    // Derived 0-100 sleep SUB-SCORES (NOT minutes).
    'sleepPerformanceScore': snapshot.sleepPerformanceScore?.round(),
    'sleepConsistencyScore': snapshot.sleepConsistencyScore?.round(),
    // Baseline / calibration coverage (counts, not biometrics).
    'baselineCoverageDays': snapshot.baselineCoverageDays,
    'isCalibrating': snapshot.isCalibrating,
    'calibrationDaysRemaining': snapshot.calibrationDaysRemaining,
    // The DERIVED acute/chronic load RATIO (rounded) — not the raw loads.
    'loadRatio': snapshot.loadRatio?.round(),
    // Derived yes/no tokens — never raw values.
    'anomalyFlags': snapshot.anomalyFlags,
    // Vetted, human-reviewed copy — the narrative's substance.
    'headline': RecoveryBandCopy.headline(snapshot),
    'guidance': RecoveryBandCopy.guidance(snapshot),
    'anomalyNote': RecoveryBandCopy.anomalyNote(snapshot),
    'whyItMatters': whyItMatters,
  };
}


/// A stable reset token for the recovery "explain my numbers" affordance, derived
/// from the FULL [recoveryExplainFacts] map. The coach note re-fetches whenever
/// this token changes, so a sync that updates ANY narrative input — not just
/// readiness / band / strain, but also confidence, sleep sub-scores, load ratio,
/// calibration coverage, anomaly flags, or the derived copy — invalidates a stale
/// note. Entries are sorted by key so map insertion order can't make two
/// equivalent fact sets produce different tokens.
String recoveryExplainResetKey(Map<String, dynamic> facts) {
  final entries = facts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((e) => '${e.key}=${e.value}').join('|');
}
