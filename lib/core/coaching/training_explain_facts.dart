/// A stable reset token for the training-balance "explain my numbers" affordance,
/// derived from the FULL training `facts` map (the same payload sent to the shared
/// `training` explain domain). The coach note re-fetches whenever this token
/// changes, so a change to ANY narrative input — not just period / balance score /
/// session count, but also region percents, lagging/dominant region, the cue text,
/// set count, or the window — invalidates a stale note. Mirrors
/// recoveryExplainResetKey (PR #381 Finding 3).
///
/// Entries are sorted by key so map insertion order can't make two equivalent fact
/// sets produce different tokens. Nested values (e.g. the `regions` list of maps)
/// are serialized via toString, which is deterministic for a fixed insertion order
/// — and the facts map always builds regions in the same DisplayRegion order.
String trainingExplainResetKey(Map<String, dynamic> facts) {
  final entries = facts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((e) => '${e.key}=${e.value}').join('|');
}
