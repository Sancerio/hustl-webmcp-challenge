/// Mutable switches shared by the in-memory demo repositories.
///
/// A single instance is created for one evaluator session. Keeping the setting
/// here makes the Connections toggle and proposal execution observe the same
/// truth without introducing a production service or network dependency.
class DemoState {
  DemoState({this.allowWebMcpFoodAutoLog = true});

  /// Whether this evaluator session is allowed to enable food auto-log.
  ///
  /// Challenge sessions lock this capability off at construction time. The
  /// setter also clamps stale or programmatic writes so every collaborator
  /// sharing this state continues to observe pending-only behavior.
  final bool allowWebMcpFoodAutoLog;

  bool _webMcpFoodAutoLog = false;

  bool get webMcpFoodAutoLog => allowWebMcpFoodAutoLog && _webMcpFoodAutoLog;

  set webMcpFoodAutoLog(bool enabled) {
    _webMcpFoodAutoLog = allowWebMcpFoodAutoLog && enabled;
  }
}
