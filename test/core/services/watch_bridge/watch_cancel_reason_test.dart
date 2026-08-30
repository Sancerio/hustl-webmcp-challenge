import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/core/services/watch_bridge/watch_bridge_service.dart';

void main() {
  // Locks the `workout_cancelled` reason wire strings. These MUST stay in sync with
  // the Swift `ConnectivityManager.CancelReason` parser:
  //   reason == "completed" -> .completed (finish, keep pending sync data)
  //   anything else / absent -> .discarded (delete the on-watch record)
  // A discard must DELETE so a thrown-away workout can't resurrect; a completion must
  // only FINISH so its pending sync data survives.
  group('WatchCancelReason.wireValue', () {
    test('discarded serializes to "discarded"', () {
      expect(WatchCancelReason.discarded.wireValue, 'discarded');
    });

    test('completed serializes to "completed"', () {
      expect(WatchCancelReason.completed.wireValue, 'completed');
    });

    test('every reason maps to a non-empty wire string', () {
      for (final reason in WatchCancelReason.values) {
        expect(reason.wireValue, isNotEmpty);
      }
    });
  });
}
