import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/notification_service.dart';
import 'package:hustl_app/main.dart';

void main() {
  group('Weekly training recap notification', () {
    late NotificationService notificationService;

    setUp(() {
      GetIt.instance.reset();
      notificationService = NotificationService();
    });

    test('recap id is distinct from the nutrition check-in id', () {
      // Two independent weekly nudges — colliding ids would let one overwrite
      // or cancel the other (the classic orphaned-notification bug).
      expect(kWeeklyTrainingRecapId, isNot(equals(kWeeklyCheckInId)));
    });

    test(
      'isWeeklyTrainingRecapScheduled is false on a non-mobile host',
      () async {
        // On the test host (not Android/iOS) scheduling is a no-op guarded by
        // the platform check, so nothing is ever pending.
        expect(await notificationService.isWeeklyTrainingRecapScheduled(),
            isFalse);
      },
    );

    testWidgets(
      'training-recap navigation lands on the Progress tab',
      (WidgetTester tester) async {
        final router = GoRouter(
          navigatorKey: navigatorKey,
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/progress',
              builder: (context, state) =>
                  const Scaffold(body: Text('Progress')),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        await notificationService.navigateToProgress();
        await tester.pumpAndSettle();

        expect(find.text('Progress'), findsOneWidget);
      },
    );
  });
}
