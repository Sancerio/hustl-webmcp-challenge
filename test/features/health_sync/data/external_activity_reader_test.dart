import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:hustl_app/features/health_sync/data/sources/external_activity_reader.dart';
import 'package:hustl_app/features/health_sync/domain/models/external_activity.dart';
import 'package:mocktail/mocktail.dart';

class _MockHealth extends Mock implements Health {}

HealthDataPoint _workoutPoint({
  required String uuid,
  HealthWorkoutActivityType activityType = HealthWorkoutActivityType.RUNNING,
  int? energy,
  int? distance,
  String sourceName = 'Strava',
  DateTime? start,
  DateTime? end,
}) {
  final s = start ?? DateTime.utc(2025, 1, 1, 8);
  final e = end ?? DateTime.utc(2025, 1, 1, 9);
  return HealthDataPoint(
    uuid: uuid,
    value: WorkoutHealthValue(
      workoutActivityType: activityType,
      totalEnergyBurned: energy,
      totalDistance: distance,
    ),
    type: HealthDataType.WORKOUT,
    unit: HealthDataUnit.NO_UNIT,
    dateFrom: s,
    dateTo: e,
    sourcePlatform: HealthPlatformType.appleHealth,
    sourceDeviceId: 'device',
    sourceId: 'com.strava',
    sourceName: sourceName,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<HealthDataType>[]);
    registerFallbackValue(<HealthDataAccess>[]);
  });

  group('externalActivityKindFromPlatform', () {
    test('maps the core platform activity types', () {
      expect(
        externalActivityKindFromPlatform('RUNNING'),
        ExternalActivityKind.run,
      );
      expect(
        externalActivityKindFromPlatform('RUNNING_TREADMILL'),
        ExternalActivityKind.run,
      );
      expect(
        externalActivityKindFromPlatform('BIKING'),
        ExternalActivityKind.ride,
      );
      expect(
        externalActivityKindFromPlatform('CYCLING'),
        ExternalActivityKind.ride,
      );
      expect(
        externalActivityKindFromPlatform('SWIMMING_OPEN_WATER'),
        ExternalActivityKind.swim,
      );
      expect(
        externalActivityKindFromPlatform('WALKING'),
        ExternalActivityKind.walk,
      );
      expect(
        externalActivityKindFromPlatform('HIKING'),
        ExternalActivityKind.hike,
      );
      expect(
        externalActivityKindFromPlatform('TRADITIONAL_STRENGTH_TRAINING'),
        ExternalActivityKind.strengthTraining,
      );
      expect(
        externalActivityKindFromPlatform('FUNCTIONAL_STRENGTH_TRAINING'),
        ExternalActivityKind.strengthTraining,
      );
      expect(
        externalActivityKindFromPlatform('HIGH_INTENSITY_INTERVAL_TRAINING'),
        ExternalActivityKind.hiit,
      );
      expect(
        externalActivityKindFromPlatform('YOGA'),
        ExternalActivityKind.yoga,
      );
      expect(
        externalActivityKindFromPlatform('PILATES'),
        ExternalActivityKind.yoga,
      );
    });

    test('is tolerant of camelCase and casing variants', () {
      expect(
        externalActivityKindFromPlatform('functionalStrengthTraining'),
        ExternalActivityKind.strengthTraining,
      );
      expect(
        externalActivityKindFromPlatform('running'),
        ExternalActivityKind.run,
      );
    });

    test('maps unknown / empty / null labels to other', () {
      expect(
        externalActivityKindFromPlatform('ARCHERY'),
        ExternalActivityKind.other,
      );
      expect(
        externalActivityKindFromPlatform('OTHER'),
        ExternalActivityKind.other,
      );
      expect(externalActivityKindFromPlatform(''), ExternalActivityKind.other);
      expect(
        externalActivityKindFromPlatform(null),
        ExternalActivityKind.other,
      );
    });
  });

  group('prettyExternalActivityName', () {
    test('prettifies raw platform activity type names', () {
      expect(prettyExternalActivityName('SOCCER'), 'Soccer');
      expect(
        prettyExternalActivityName('AMERICAN_FOOTBALL'),
        'American football',
      );
      expect(prettyExternalActivityName('TABLE_TENNIS'), 'Table tennis');
    });

    test('keeps the real name for recognized kinds (no re-flattening)', () {
      // These map to a coarse ExternalActivityKind, but the receipt still shows
      // the platform's own specific name rather than the generic kind label.
      expect(prettyExternalActivityName('TENNIS'), 'Tennis');
      expect(prettyExternalActivityName('PILATES'), 'Pilates'); // not "Yoga"
      expect(prettyExternalActivityName('RUNNING'), 'Running');
      expect(prettyExternalActivityName('BIKING'), 'Biking'); // not "Ride"
    });

    test('shortens the few long / awkward names via curated short forms', () {
      expect(prettyExternalActivityName('STRENGTH_TRAINING'), 'Strength');
      expect(
        prettyExternalActivityName('TRADITIONAL_STRENGTH_TRAINING'),
        'Strength',
      );
      expect(
        prettyExternalActivityName('HIGH_INTENSITY_INTERVAL_TRAINING'),
        'HIIT',
      );
      expect(prettyExternalActivityName('RUNNING_TREADMILL'), 'Treadmill run');
      expect(
        prettyExternalActivityName('STAIR_CLIMBING_MACHINE'),
        'Stair climbing',
      );
      expect(
        prettyExternalActivityName('BIKING_STATIONARY'),
        'Stationary bike',
      );
      expect(
        prettyExternalActivityName('WHEELCHAIR_RUN_PACE'),
        'Wheelchair run',
      );
    });

    test('returns null for the catch-all types and empty/null input', () {
      expect(prettyExternalActivityName('OTHER'), isNull);
      expect(prettyExternalActivityName('UNKNOWN'), isNull);
      expect(prettyExternalActivityName(''), isNull);
      expect(prettyExternalActivityName(null), isNull);
    });

    test('handles camelCase, and separator-only / padded inputs', () {
      // camelCase (Health Connect can emit this variant).
      expect(
        prettyExternalActivityName('americanFootball'),
        'American football',
      );
      // Punctuation-only reduces to nothing -> no real name.
      expect(prettyExternalActivityName('---'), isNull);
      // Leading/trailing separators are trimmed, not doubled into blank words.
      expect(prettyExternalActivityName('--SOCCER--'), 'Soccer');
    });
  });

  group('ExternalActivityReader.mapWorkoutPoint', () {
    test('projects uuid, source, kind, times, energy and distance', () {
      final point = _workoutPoint(
        uuid: 'w1',
        activityType: HealthWorkoutActivityType.RUNNING,
        energy: 420,
        distance: 8000,
        sourceName: 'Strava',
      );
      final a = ExternalActivityReader.mapWorkoutPoint(point);
      expect(a.platformUuid, 'w1');
      expect(a.sourceName, 'Strava');
      expect(a.kind, ExternalActivityKind.run);
      expect(a.activeEnergyKcal, 420);
      expect(a.distanceMeters, 8000);
      expect(a.averageHeartRateBpm, isNull);
      expect(a.start, DateTime.utc(2025, 1, 1, 8));
      expect(a.end, DateTime.utc(2025, 1, 1, 9));
      expect(a.durationMinutes, closeTo(60, 0.001));
    });

    test('treats zero/absent energy and distance as null', () {
      final point = _workoutPoint(
        uuid: 'w2',
        activityType: HealthWorkoutActivityType.YOGA,
        energy: 0,
        distance: null,
      );
      final a = ExternalActivityReader.mapWorkoutPoint(point);
      expect(a.kind, ExternalActivityKind.yoga);
      expect(a.activeEnergyKcal, isNull);
      expect(a.distanceMeters, isNull);
    });

    test('an unrecognized sport (soccer) preserves the real activity name', () {
      final point = _workoutPoint(
        uuid: 'w3',
        activityType: HealthWorkoutActivityType.SOCCER,
      );
      final a = ExternalActivityReader.mapWorkoutPoint(point);
      expect(a.kind, ExternalActivityKind.other);
      expect(a.activityName, 'Soccer');
    });

    test('a recognized kind still carries its real activity name', () {
      final point = _workoutPoint(
        uuid: 'w4',
        activityType: HealthWorkoutActivityType.RUNNING,
      );
      final a = ExternalActivityReader.mapWorkoutPoint(point);
      expect(a.kind, ExternalActivityKind.run);
      expect(a.activityName, 'Running');
    });

    test('Pilates keeps its name instead of being flattened to Yoga', () {
      final point = _workoutPoint(
        uuid: 'w5',
        activityType: HealthWorkoutActivityType.PILATES,
      );
      final a = ExternalActivityReader.mapWorkoutPoint(point);
      // Coarse kind is still yoga (drives load factors), but the display name
      // stays "Pilates".
      expect(a.kind, ExternalActivityKind.yoga);
      expect(a.activityName, 'Pilates');
    });

    test('the platform catch-all (other) carries no name -> "Workout"', () {
      final point = _workoutPoint(
        uuid: 'w6',
        activityType: HealthWorkoutActivityType.OTHER,
      );
      final a = ExternalActivityReader.mapWorkoutPoint(point);
      expect(a.kind, ExternalActivityKind.other);
      expect(a.activityName, isNull);
    });
  });

  group('ExternalActivityReader.readActivities window semantics', () {
    late _MockHealth health;
    late ExternalActivityReader reader;

    // The requested day window: [Jan 2 00:00, Jan 3 00:00).
    final windowStart = DateTime.utc(2025, 1, 2);
    final windowEnd = DateTime.utc(2025, 1, 3);

    setUp(() {
      health = _MockHealth();
      reader = ExternalActivityReader(health: health);
      when(health.configure).thenAnswer((_) async {});
      // The read path is SILENT: it probes hasPermissions and must never call
      // requestAuthorization (asserted per-test below and in the silent-gate
      // group).
      when(
        () => health.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
    });

    void stubPoints(List<HealthDataPoint> points) {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => points);
    }

    test('crossing-midnight workout (23:30 -> 00:30) IS returned', () async {
      stubPoints([
        _workoutPoint(
          uuid: 'midnight-run',
          start: DateTime.utc(2025, 1, 1, 23, 30),
          end: DateTime.utc(2025, 1, 2, 0, 30),
        ),
      ]);

      final activities = await reader.readActivities(
        start: windowStart,
        end: windowEnd,
      );
      expect(activities.map((a) => a.platformUuid), ['midnight-run']);
    });

    test('workout entirely inside the previous day is NOT returned', () async {
      stubPoints([
        _workoutPoint(
          uuid: 'yesterday',
          start: DateTime.utc(2025, 1, 1, 18),
          end: DateTime.utc(2025, 1, 1, 19),
        ),
      ]);

      final activities = await reader.readActivities(
        start: windowStart,
        end: windowEnd,
      );
      expect(activities, isEmpty);
    });

    test('plugin query receives the padded start', () async {
      stubPoints(const []);

      await reader.readActivities(start: windowStart, end: windowEnd);

      verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: windowStart.subtract(
            ExternalActivityReader.maxWorkoutLookback,
          ),
          endTime: windowEnd,
        ),
      ).called(1);
    });
  });

  group('ExternalActivityReader silent permission gate', () {
    late _MockHealth health;
    late ExternalActivityReader reader;

    final windowStart = DateTime.utc(2025, 1, 2);
    final windowEnd = DateTime.utc(2025, 1, 3);

    setUp(() {
      health = _MockHealth();
      reader = ExternalActivityReader(health: health);
      when(health.configure).thenAnswer((_) async {});
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _workoutPoint(
            uuid: 'w1',
            start: DateTime.utc(2025, 1, 2, 8),
            end: DateTime.utc(2025, 1, 2, 9),
          ),
        ],
      );
    });

    void stubHasPermissions(bool? value) {
      when(
        () => health.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => value);
    }

    /// The load path must NEVER pop an OS dialog from a passive surface.
    void expectNeverPrompted() {
      verifyNever(
        () => health.requestAuthorization(
          any(),
          permissions: any(named: 'permissions'),
        ),
      );
    }

    test('NEVER calls requestAuthorization, even when granted', () async {
      stubHasPermissions(true);

      final activities = await reader.readActivities(
        start: windowStart,
        end: windowEnd,
      );

      expect(activities, hasLength(1));
      expectNeverPrompted();
    });

    test('permission false → empty read, no prompt', () async {
      stubHasPermissions(false);

      final activities = await reader.readActivities(
        start: windowStart,
        end: windowEnd,
      );

      expect(activities, isEmpty);
      expectNeverPrompted();
      verifyNever(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      );
    });

    test('permission undetermined (null, iOS) → silent query IS attempted, '
        'requestAuthorization never called', () async {
      // iOS/HealthKit hides read grants by design, so the probe is ALWAYS
      // null there. The reader must still attempt the silent query (an
      // unauthorized HealthKit read is prompt-free and simply returns no
      // data) — treating null as "denied" would permanently disable external
      // workouts on iOS.
      stubHasPermissions(null);

      final activities = await reader.readActivities(
        start: windowStart,
        end: windowEnd,
      );

      // The query was issued and its data flowed through.
      expect(activities, hasLength(1));
      verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).called(1);
      expectNeverPrompted();
    });

    test('permission probe throws → empty read, no prompt', () async {
      when(
        () => health.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenThrow(Exception('platform channel down'));

      final activities = await reader.readActivities(
        start: windowStart,
        end: windowEnd,
      );

      expect(activities, isEmpty);
      expectNeverPrompted();
    });
  });
}
