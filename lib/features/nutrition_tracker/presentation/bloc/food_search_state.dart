import 'package:equatable/equatable.dart';

import '../../domain/models/food.dart';

class FoodSearchState extends Equatable {
  const FoodSearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.errorMessage,
    this.isStale = false,
    this.staleAgeMs,
  });

  final String query;
  final List<Food> results;
  final bool isLoading;
  final String? errorMessage;

  /// True when the backend fell back to past-TTL cached provider results
  /// (provider timed out or errored). The UI surfaces this as a soft
  /// "showing saved results — tap to refresh" banner rather than a failure.
  final bool isStale;

  /// Age of the stale cache in milliseconds, when known. Drives the
  /// human-readable label in [staleAgeDisplay].
  final int? staleAgeMs;

  /// Human-readable age of the saved results, e.g. "saved 30 minutes ago".
  /// Falls back to "saved earlier" when the age is unknown or zero.
  String staleAgeDisplay() {
    final ageMs = staleAgeMs;
    if (ageMs == null || ageMs <= 0) return 'saved earlier';

    final seconds = ageMs ~/ 1000;
    if (seconds < 60) return 'saved just now';

    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return 'saved $minutes ${_plural(minutes, 'minute')} ago';
    }

    final hours = minutes ~/ 60;
    if (hours < 24) {
      return 'saved $hours ${_plural(hours, 'hour')} ago';
    }

    final days = hours ~/ 24;
    return 'saved $days ${_plural(days, 'day')} ago';
  }

  static String _plural(int value, String unit) =>
      value == 1 ? unit : '${unit}s';

  FoodSearchState copyWith({
    String? query,
    List<Food>? results,
    bool? isLoading,
    String? errorMessage,
    bool? isStale,
    int? staleAgeMs,
  }) {
    final nextIsStale = isStale ?? this.isStale;
    return FoodSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isStale: nextIsStale,
      // The age is only meaningful while stale; clear it on any transition back
      // to fresh so a refreshed search never carries an old timestamp.
      staleAgeMs: nextIsStale ? (staleAgeMs ?? this.staleAgeMs) : null,
    );
  }

  @override
  List<Object?> get props => [
    query,
    results,
    isLoading,
    errorMessage,
    isStale,
    staleAgeMs,
  ];
}
