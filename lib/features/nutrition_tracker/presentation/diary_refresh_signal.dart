import 'package:flutter/foundation.dart';

/// A lightweight app-wide "the diary changed" broadcast.
///
/// The diary's [DiaryBloc] is created per-screen (not a get_it singleton) and
/// the live [DiaryScreen] is kept alive in the shell's IndexedStack, so it only
/// reloads on its own events. The global one-tap "/add-food" flow persists
/// entries through the repository directly — outside any reachable bloc — so the
/// already-mounted diary would otherwise miss the new food until a manual
/// refresh.
///
/// This notifier bridges that gap: the global save pings it on success and the
/// diary listens, dispatching a reload of its current day. Registered as a
/// get_it singleton so both ends resolve the same instance regardless of where
/// they sit in the widget tree.
class DiaryRefreshSignal extends ChangeNotifier {
  /// Announce that the diary's underlying data changed and any live listener
  /// should reload.
  void ping() => notifyListeners();
}
