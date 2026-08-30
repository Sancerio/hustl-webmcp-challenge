@TestOn('browser')
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/services/notification_service.dart';

void main() {
  group('NotificationService on web', () {
    test('init completes without throwing', () async {
      final service = NotificationService();
      await service.init();
    });

    test('showRestComplete is a no-op and does not throw', () async {
      final service = NotificationService();
      await service.showRestComplete(exerciseName: 'Bench Press');
    });
  });
}
