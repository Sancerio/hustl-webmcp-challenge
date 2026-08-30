import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/data/services/health_cache_service.dart';
import 'package:hustl_app/features/health_sync/domain/models/health_metric_sample.dart';

void main() {
  test(
    'round-trips cached health observations through background encode/decode',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService()..resetForTests();
      final service = HealthCacheService(preferences);
      final start = DateTime(2026, 8, 17);
      final end = DateTime(2026, 8, 18);
      final fetchedAt = DateTime(2026, 8, 18, 8);

      await service.saveSnapshot(
        start: start,
        end: end,
        metrics: [
          HealthMetricSample(
            type: HealthMetricType.heartRateVariabilitySdnn,
            value: 48,
            unit: 'ms',
            startTime: DateTime(2026, 8, 18, 6),
            endTime: DateTime(2026, 8, 18, 6, 1),
            source: 'Apple Watch',
            sourceId: 'watch-source',
            deviceModel: 'Watch',
          ),
        ],
        nutrition: const [],
        fetchedAt: fetchedAt,
        warnings: const ['test warning'],
      );

      final loaded = await service.loadSnapshot();

      expect(loaded, isNotNull);
      expect(loaded!.rangeStart, start);
      expect(loaded.rangeEnd, end);
      expect(loaded.lastSyncedAt, fetchedAt);
      expect(loaded.warnings, const ['test warning']);
      expect(loaded.metrics, hasLength(1));
      expect(
        loaded.metrics.single.type,
        HealthMetricType.heartRateVariabilitySdnn,
      );
      expect(loaded.metrics.single.value, 48);
      expect(loaded.metrics.single.sourceId, 'watch-source');
    },
  );
}
