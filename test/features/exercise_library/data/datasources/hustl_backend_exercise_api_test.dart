import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:hustl_app/features/exercise_library/data/datasources/hustl_backend_exercise_api.dart';
import 'package:hustl_app/features/exercise_library/domain/models/exercise.dart';

class _FakeClient extends http.BaseClient {
  final Map<String, dynamic> body;
  _FakeClient(this.body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _RecordingClient extends http.BaseClient {
  Map<String, String>? headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    headers = Map<String, String>.from(request.headers);
    final bytes = utf8.encode(
      jsonEncode({
        'success': true,
        'data': {'uploads': <Object>[]},
      }),
    );
    return http.StreamedResponse(Stream.value(bytes), 200, request: request);
  }
}

Map<String, dynamic> _wrapItems(List<Map<String, dynamic>> items) => {
  'success': true,
  'data': {'items': items, 'limit': 1000, 'offset': 0},
};

void main() {
  test('debug generation sends the configured backend debug token', () async {
    final client = _RecordingClient();
    final api = HustlBackendExerciseApi(
      client: client,
      baseUrl: 'https://example',
      debugToken: 'local-debug-token',
    );

    await api.regenerateThumbnail(id: 'exercise-1', accessToken: 'access');

    expect(client.headers?['x-debug-token'], 'local-debug-token');
    expect(client.headers?['Authorization'], 'Bearer access');
  });

  test('maps fallback muscles when none provided', () async {
    final items = [
      // 1) category fallback
      {
        'id': '1',
        'name': 'Tiptoe Lunge',
        'category': 'therapy',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      // 2) movement pattern fallback when category unknown
      {
        'id': '2',
        'name': 'Hinge Drill',
        'category': 'unknown',
        'movement_pattern': 'hinge',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      // 3) mechanic fallback when others missing/unknown
      {
        'id': '3',
        'name': 'Compound Test',
        'category': null,
        'movement_pattern': null,
        'mechanic': 'compound',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      // 4) default to General
      {
        'id': '4',
        'name': 'No Meta',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      // 5) preserves provided muscles (title-cased)
      {
        'id': '5',
        'name': 'Provided',
        'primary_muscles': ['quads'],
        'secondary_muscles': ['rear delts'],
      },
    ];

    final client = _FakeClient(_wrapItems(items));
    final api = HustlBackendExerciseApi(
      client: client,
      baseUrl: 'https://example',
    );

    final result = await api.listExercises(limit: 10);
    expect(result.length, 5);

    Exercise getBy(String id) => result.firstWhere((e) => e.id == id);

    expect(getBy('1').muscles, ['Therapy']);
    expect(getBy('2').muscles, ['Hinge']);
    expect(getBy('3').muscles, ['Compound']);
    expect(getBy('4').muscles, ['General']);
    expect(getBy('5').muscles, ['Quads', 'Rear Delts']);
  });

  test('maps exercise kind case-insensitively', () async {
    final items = [
      {
        'id': '1',
        'name': 'Run',
        'kind': 'Cardio',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      {
        'id': '2',
        'name': 'Assisted Pull-up',
        'kind': 'ASSISTED',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      {
        'id': '3',
        'name': 'Bench Press',
        'kind': 'Strength',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      {
        'id': '4',
        'name': 'No Kind Provided',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
    ];

    final client = _FakeClient(_wrapItems(items));
    final api = HustlBackendExerciseApi(
      client: client,
      baseUrl: 'https://example',
    );

    final result = await api.listExercises(limit: 10);
    expect(result.length, 4);

    Exercise getBy(String id) => result.firstWhere((e) => e.id == id);

    expect(getBy('1').kind, ExerciseKind.cardio);
    expect(getBy('2').kind, ExerciseKind.assisted);
    expect(getBy('3').kind, ExerciseKind.strength);
    expect(getBy('4').kind, ExerciseKind.strength);
  });

  test('maps logging_mode to ExerciseLoggingMode', () async {
    final items = [
      {
        'id': '1',
        'name': 'Plank',
        'kind': 'strength',
        'logging_mode': 'duration_only',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
      {
        'id': '2',
        'name': 'Run',
        'kind': 'cardio',
        'logging_mode': 'distance_duration',
        'primary_muscles': [],
        'secondary_muscles': [],
      },
    ];

    final client = _FakeClient(_wrapItems(items));
    final api = HustlBackendExerciseApi(
      client: client,
      baseUrl: 'https://example',
    );

    final result = await api.listExercises(limit: 10);
    Exercise getBy(String id) => result.firstWhere((e) => e.id == id);

    expect(getBy('1').loggingMode, ExerciseLoggingMode.durationOnly);
    expect(getBy('2').loggingMode, ExerciseLoggingMode.distanceDuration);
  });

  test('Exercise.fromMap parses kind case-insensitively', () {
    final cardio = Exercise.fromMap({
      'name': 'Plank',
      'muscles': ['Core'],
      'kind': 'CARDIO',
    });
    expect(cardio.kind, ExerciseKind.cardio);

    final strength = Exercise.fromMap({
      'name': 'Bench',
      'muscles': ['Chest'],
      'kind': 'Strength',
    });
    expect(strength.kind, ExerciseKind.strength);
  });
}
