import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/health_connect_primer.dart';

/// Records whether the real OS permission request was made.
class _FakeHealthMetricsRepository implements HealthMetricsRepository {
  int requestCount = 0;

  @override
  Future<HealthPermissionsStatus> requestPermissions() async {
    requestCount++;
    return const HealthPermissionsStatus(
      hasPermissions: true,
      isServiceAvailable: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<void> _pump(
  WidgetTester tester, {
  required PreferencesService prefs,
  required _FakeHealthMetricsRepository repo,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => maybeRunHealthConnectPrimer(
                context,
                preferences: prefs,
                healthMetricsRepository: repo,
              ),
              child: const Text('Log weight'),
            ),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
}

void main() {
  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
  });

  testWidgets(
    'shows the primer once, declining proceeds without an OS request, then '
    'the pref suppresses it',
    (tester) async {
      final repo = _FakeHealthMetricsRepository();
      await _pump(tester, prefs: prefs, repo: repo);

      // First weight-log: the primer appears.
      await tester.tap(find.text('Log weight'));
      await tester.pumpAndSettle();
      expect(find.text('Log manually instead'), findsOneWidget);

      // "Log manually instead" proceeds to the manual save with no OS request.
      await tester.tap(find.text('Log manually instead'));
      await tester.pumpAndSettle();
      expect(repo.requestCount, 0);
      expect(prefs.seenHealthConnectPrimer, isTrue);

      // Second weight-log: the pref suppresses the primer entirely.
      await tester.tap(find.text('Log weight'));
      await tester.pumpAndSettle();
      expect(find.text('Log manually instead'), findsNothing);
    },
  );

  testWidgets('Connect requests the real OS permission, then is suppressed', (
    tester,
  ) async {
    final repo = _FakeHealthMetricsRepository();
    await _pump(tester, prefs: prefs, repo: repo);

    await tester.tap(find.text('Log weight'));
    await tester.pumpAndSettle();

    // FilledButton.icon's runtime type is a private subtype, so match by
    // subtype; the primer's only filled button is the Connect CTA.
    await tester.tap(find.bySubtype<FilledButton>());
    await tester.pumpAndSettle();

    expect(repo.requestCount, 1);
    expect(prefs.seenHealthConnectPrimer, isTrue);

    // Already seen — a later weight-log does not re-show it or re-request.
    await tester.tap(find.text('Log weight'));
    await tester.pumpAndSettle();
    expect(find.text('Log manually instead'), findsNothing);
    expect(repo.requestCount, 1);
  });
}
