import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/network/http_client.dart';
import '../../domain/services/body_score_service.dart';

class BodyScoreApi {
  BodyScoreApi({http.Client? client, String? baseUrl})
    : _client = client ?? createHttpClient(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<BodyScoreSummary?> fetchLatest({int windowDays = 30}) async {
    final uri = Uri.parse(
      '$_baseUrl/api/progress/body-score',
    ).replace(queryParameters: {'window_days': windowDays.toString()});
    final res = await _client.get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Body score request failed: ${res.statusCode} ${res.reasonPhrase}',
      );
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    if (data == null) {
      return null;
    }

    final windowStart = DateTime.tryParse(
      data['window_start'] as String? ?? '',
    );
    final windowEnd = DateTime.tryParse(data['window_end'] as String? ?? '');
    if (windowStart == null || windowEnd == null) {
      return null;
    }

    final rawVolumes = (data['region_volumes'] as Map<String, dynamic>?) ?? {};
    final Map<MuscleGroup, double> volumes = {};
    for (final entry in rawVolumes.entries) {
      final value = (entry.value as num?)?.toDouble() ?? 0.0;
      final parsed = muscleGroupFromKey(entry.key);
      if (parsed != null) {
        volumes.update(
          parsed,
          (existing) => existing + value,
          ifAbsent: () => value,
        );
        continue;
      }

      final distributed = _legacyRegionDistribution(entry.key);
      if (distributed == null) continue;
      for (final portion in distributed.entries) {
        final weighted = value * portion.value;
        if (weighted == 0) continue;
        volumes.update(
          portion.key,
          (existing) => existing + weighted,
          ifAbsent: () => weighted,
        );
      }
    }

    final dominantKey = data['dominant_region'] as String? ?? '';
    final summary = BodyScoreSummary.calculate(
      volumes: volumes,
      window: DateTimeRange(start: windowStart, end: windowEnd),
      sessionCount: (data['session_count'] as num?)?.toInt() ?? 0,
      balanceOverride: (data['balance_score'] as num?)?.toDouble(),
      dominantOverride:
          muscleGroupFromKey(dominantKey) ??
          _legacyRegionRepresentative(dominantKey) ??
          MuscleGroup.other,
    );
    return summary;
  }

  static MuscleGroup? _legacyRegionRepresentative(String key) {
    final distribution = _legacyRegionDistribution(key);
    if (distribution == null || distribution.isEmpty) return null;
    return distribution.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  static Map<MuscleGroup, double>? _legacyRegionDistribution(String key) {
    final groups = switch (key.toLowerCase()) {
      'chest' => const [
        MuscleGroup.upperPecs,
        MuscleGroup.middlePecs,
        MuscleGroup.lowerPecs,
      ],
      'back' => const [
        MuscleGroup.lats,
        MuscleGroup.upperTraps,
        MuscleGroup.lowerTraps,
        MuscleGroup.rhomboids,
        MuscleGroup.lowerBack,
      ],
      'shoulders' => const [
        MuscleGroup.frontDelts,
        MuscleGroup.sideDelts,
        MuscleGroup.rearDelts,
      ],
      'arms' => const [
        MuscleGroup.biceps,
        MuscleGroup.triceps,
        MuscleGroup.forearms,
      ],
      'core' => const [
        MuscleGroup.upperAbs,
        MuscleGroup.lowerAbs,
        MuscleGroup.obliques,
      ],
      'legs' => const [
        MuscleGroup.quads,
        MuscleGroup.hamstrings,
        MuscleGroup.glutes,
        MuscleGroup.calves,
        MuscleGroup.hipAbductors,
        MuscleGroup.hipAdductors,
        MuscleGroup.hipFlexors,
      ],
      'other' => const [
        MuscleGroup.neck,
        MuscleGroup.other,
        MuscleGroup.fullBody,
      ],
      _ => null,
    };
    if (groups == null || groups.isEmpty) return null;

    var totalWeight = 0.0;
    final weights = <MuscleGroup, double>{};
    for (final group in groups) {
      final weight = defaultWeeklyTargetsByMuscleGroup[group] ?? 0.0;
      if (weight <= 0) continue;
      weights[group] = weight;
      totalWeight += weight;
    }

    if (weights.isEmpty) {
      final equal = 1.0 / groups.length;
      return {for (final group in groups) group: equal};
    }

    return {
      for (final entry in weights.entries) entry.key: entry.value / totalWeight,
    };
  }
}
