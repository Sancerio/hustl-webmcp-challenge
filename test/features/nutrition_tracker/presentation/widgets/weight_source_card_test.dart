import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/domain/repositories/health_metrics_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/weight_source_card.dart';
import 'dart:async';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets(
    'shows connected when permissions granted even without backend sources',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          WeightSourceCard(
            healthSources: const [],
            permissionsFuture: Future.value(
              const HealthPermissionsStatus(
                hasPermissions: true,
                isServiceAvailable: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Manage'), findsOneWidget);
      expect(find.text('Not connected.'), findsNothing);
      expect(find.textContaining('Connected'), findsOneWidget);
    },
  );

  testWidgets('does not flash Not connected while loading permissions', (
    tester,
  ) async {
    final completer = Completer<HealthPermissionsStatus>();
    await tester.pumpWidget(
      wrap(
        WeightSourceCard(
          healthSources: const [],
          permissionsFuture: completer.future,
        ),
      ),
    );

    // First frame: future is still pending.
    expect(find.text('Not connected.'), findsNothing);
    expect(find.text('Checking connection…'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    completer.complete(
      const HealthPermissionsStatus(
        hasPermissions: false,
        isServiceAvailable: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not connected.'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('shows not connected when permissions denied', (tester) async {
    await tester.pumpWidget(
      wrap(
        WeightSourceCard(
          healthSources: const [],
          permissionsFuture: Future.value(
            const HealthPermissionsStatus(
              hasPermissions: false,
              isServiceAvailable: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Not connected.'), findsOneWidget);
  });

  testWidgets('backend sources take precedence when present', (tester) async {
    await tester.pumpWidget(
      wrap(
        WeightSourceCard(
          healthSources: const [
            {
              'provider': 'apple_health',
              'last_synced_at': '2024-06-10T12:00:00.000Z',
            },
          ],
          permissionsFuture: Future.value(
            const HealthPermissionsStatus(
              hasPermissions: false,
              isServiceAvailable: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Not connected.'), findsNothing);
    expect(find.textContaining('Last synced:'), findsOneWidget);
  });
}
