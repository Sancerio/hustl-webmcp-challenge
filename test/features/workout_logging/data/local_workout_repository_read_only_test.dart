import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/workout_logging/data/repositories/local_workout_repository.dart';
import 'package:hustl_app/features/workout_logging/domain/models/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'read-only snapshot never repairs or persists workout storage',
    () async {
      final active = WorkoutSession(
        id: 'active-1',
        name: 'Push day',
        startTime: DateTime.utc(2026, 8, 26, 8),
        exercises: const [],
        isCompleted: false,
      );
      final encoded = jsonEncode([active.toMap()]);
      SharedPreferences.setMockInitialValues({'workout_sessions_v1': encoded});
      final prefs = await SharedPreferences.getInstance();
      final keysBefore = prefs.getKeys();

      final snapshot = await LocalWorkoutRepository()
          .getWorkoutSnapshotReadOnly(limit: 25);

      expect(snapshot.activeSession?.id, 'active-1');
      expect(snapshot.sessions.single.id, 'active-1');
      expect(prefs.getKeys(), keysBefore);
      expect(prefs.getString('workout_sessions_v1'), encoded);
      expect(
        prefs.containsKey('workout_sessions_v1_active_session_id'),
        isFalse,
      );
    },
  );
}
