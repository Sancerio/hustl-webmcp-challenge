/// Effort is STORED as RPE (rate of perceived exertion, 1–10) but SHOWN to the
/// user as RIR (reps in reserve, 0–6+). `RIR = 10 − RPE`, and the top of the
/// scale renders as "6+".
///
/// This is the single source of truth for that mapping while the RIR migration
/// lives in the frontend only (the persisted/synced field stays `rpe`). When the
/// backend migrates to RIR, callers move off this and the stored field changes.
class EffortScale {
  EffortScale._();

  /// Top of the RIR scale (rendered as "6+").
  static const int maxRir = 6;

  /// RIR (0–[maxRir]) for a stored RPE, or null. Clamped into `[0, maxRir]`.
  static int? rirFromRpe(int? rpe) =>
      rpe == null ? null : (10 - rpe).clamp(0, maxRir);

  /// Stored RPE for a chosen RIR, or null.
  static int? rpeFromRir(int? rir) => rir == null ? null : 10 - rir;

  /// Display label for a RIR value (`2`, or `6+` at the top of the scale).
  static String rirLabel(int rir) => rir >= maxRir ? '$maxRir+' : '$rir';

  /// Display label for a stored RPE shown as RIR (e.g. `2`, `6+`), or null.
  static String? rirLabelFromRpe(int? rpe) {
    final rir = rirFromRpe(rpe);
    return rir == null ? null : rirLabel(rir);
  }
}
