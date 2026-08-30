/// Mutable switches shared by the in-memory demo repositories.
///
/// A single instance is created for one evaluator session. Keeping the setting
/// here makes the Connections toggle and proposal execution observe the same
/// truth without introducing a production service or network dependency.
class DemoState {
  bool webMcpFoodAutoLog = false;
}
