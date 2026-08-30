import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hustl_app/core/services/token_storage.dart' as token;
import 'package:hustl_app/features/workout_logging/data/datasources/hustl_backend_workout_exercise_stats_api.dart';

class _FakeTokenStorage implements token.TokenStorage {
  _FakeTokenStorage(this._access);

  String? _access;

  @override
  Future<String?> getAccessToken() async => _access;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokenPair({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    _access = accessToken;
  }

  @override
  Future<void> clearAccessToken() async {
    _access = null;
  }

  @override
  Future<void> clearAll() async {
    _access = null;
  }
}

void main() {
  group('HustlBackendWorkoutExerciseStatsApi previous sets', () {
    test('maps distance/duration into weight/reps', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'sets': [
                {
                  'id': 's1',
                  'set_number': 1,
                  // distance column is metres (backend contract); app maps to km.
                  'distance': 1750,
                  'duration': 420,
                  'weight': null,
                  'reps': null,
                  'rpe': null,
                  'is_completed': true,
                  'set_type': 'regular',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = HustlBackendWorkoutExerciseStatsApi(
        client: client,
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage('token'),
      );

      final sets = await api.fetchPreviousExerciseSets('Run');
      expect(sets, hasLength(1));
      expect(sets.single.weight, 1.75); // 1750 m -> 1.75 km
      expect(sets.single.reps, 420);
    });

    test('keeps weight/reps for non-cardio rows', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'sets': [
                {
                  'id': 's2',
                  'set_number': 1,
                  'weight': 100,
                  'reps': 5,
                  'duration': null,
                  'distance': null,
                  'rpe': 8,
                  'is_completed': true,
                  'set_type': 'regular',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = HustlBackendWorkoutExerciseStatsApi(
        client: client,
        baseUrl: 'https://example.com',
        tokens: _FakeTokenStorage('token'),
      );

      final sets = await api.fetchPreviousExerciseSets('Bench Press');
      expect(sets, hasLength(1));
      expect(sets.single.weight, 100);
      expect(sets.single.reps, 5);
      expect(sets.single.rpe, 8);
    });
  });
}
