import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../../workout_logging/domain/models/workout_session.dart';
import 'body_score_service.dart';

/// Serializable request for the heavy body-score aggregation. Only plain data
/// crosses the isolate boundary — strategies are rebuilt by id inside the
/// isolate so no closures are transferred.
@immutable
class BodyScoreComputeRequest {
  const BodyScoreComputeRequest({
    required this.sessions,
    required this.strategyIds,
    required this.windowRange,
    required this.heatmapRange,
  });

  final List<WorkoutSession> sessions;
  final List<String> strategyIds;
  final DateTimeRange windowRange;
  final DateTimeRange heatmapRange;
}

/// Result of [computeBodyScoreSummaries]: per-strategy summaries for both the
/// selected window and the rolling heatmap window.
///
/// Each [BodyScoreSummary] now also carries the Phase 3 raw [BodyScoreSummary.setsByGroup]
/// (per-group RAW set counts, matching [BodyScoreService.aggregateForRange]) and
/// the Phase 4 integer [BodyScoreSummary.physicalSetsByGroup], so raw sets flow
/// through this isolate/compute path and callers no longer need a separate
/// `aggregateForRange` pass for the current-week raw-set figures.
@immutable
class BodyScoreComputeResult {
  const BodyScoreComputeResult({
    required this.windowSummaries,
    required this.heatmapSummaries,
  });

  final Map<String, BodyScoreSummary?> windowSummaries;
  final Map<String, BodyScoreSummary?> heatmapSummaries;
}

BodyScoreService _serviceForStrategyId(String id) {
  final strategy = BodyScoreStrategies.defaults.firstWhere(
    (s) => s.id == id,
    orElse: () => BodyScoreStrategies.effectiveSets,
  );
  return BodyScoreService(
    config: BodyScoreConfig(loadStrategy: strategy.loadStrategy),
  );
}

/// Pure, isolate-safe aggregation. Rebuilds services from strategy ids and runs
/// the O(sessions × exercises × sets) [BodyScoreService.summarize] work.
BodyScoreComputeResult runBodyScoreCompute(BodyScoreComputeRequest request) {
  final windowSummaries = <String, BodyScoreSummary?>{};
  final heatmapSummaries = <String, BodyScoreSummary?>{};
  for (final id in request.strategyIds) {
    final service = _serviceForStrategyId(id);
    windowSummaries[id] = service.summarize(
      request.sessions,
      range: request.windowRange,
    );
    heatmapSummaries[id] = service.summarize(
      request.sessions,
      range: request.heatmapRange,
    );
  }
  return BodyScoreComputeResult(
    windowSummaries: windowSummaries,
    heatmapSummaries: heatmapSummaries,
  );
}

/// Offloads [runBodyScoreCompute] to a background isolate. Falls back to a
/// synchronous run on platforms without isolate support (web).
Future<BodyScoreComputeResult> computeBodyScoreSummaries(
  BodyScoreComputeRequest request,
) {
  if (kIsWeb) {
    return Future.value(runBodyScoreCompute(request));
  }
  return compute(runBodyScoreCompute, request);
}
