import 'package:get_it/get_it.dart';

import 'diary_refresh_signal.dart';

/// A tiny in-memory cache of the last-loaded result for the read-heavy nutrition
/// analytics screens (insights, weight trend, strategy).
///
/// These screens re-fetch in `initState` on every visit, so without a cache they
/// flash a full skeleton each time. With it they paint instantly from the last
/// result and revalidate behind a thin progress line (stale-while-revalidate).
/// The cache is CLEARED whenever the diary changes (a new/edited/removed food
/// log fires [DiaryRefreshSignal]), so analytics never serve stale numbers after
/// a mutation; every screen open also revalidates regardless, so the cache can
/// never go permanently stale.
class NutritionViewCache {
  NutritionViewCache._() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<DiaryRefreshSignal>()) {
      getIt<DiaryRefreshSignal>().addListener(clear);
    }
  }

  static final NutritionViewCache instance = NutritionViewCache._();

  final Map<String, Object> _store = {};

  T? get<T>(String key) => _store[key] as T?;

  void set(String key, Object value) => _store[key] = value;

  /// Drops everything — called on a diary change, and usable as a test reset.
  void clear() => _store.clear();
}
