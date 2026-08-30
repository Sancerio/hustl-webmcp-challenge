import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/features/health_sync/domain/models/recovery_signal_availability.dart';
import 'package:hustl_app/features/health_sync/presentation/screens/connect_health_page.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/recovery_signal_prompt.dart';

void main() {
  group('RecoverySignalAvailability', () {
    test('empty default reads as no signals, provider assumed reachable', () {
      const availability = RecoverySignalAvailability.empty;
      expect(availability.hasAnySignal, isFalse);
      expect(availability.hasAllSignals, isFalse);
      expect(
        availability.providerAvailability,
        HealthProviderAvailability.available,
      );
    });

    test(
      'missingSignals lists the absent core signals, not respiratory yet',
      () {
        const availability = RecoverySignalAvailability(
          hrv: false,
          restingHeartRate: true,
          sleep: true,
          respiratoryRate: false,
        );
        // Core HRV is missing; respiratory is held back until the core 3 land.
        expect(availability.missingSignals, [RecoverySignal.hrv]);
      },
    );

    test('respiratory is surfaced only once the core three are flowing', () {
      const availability = RecoverySignalAvailability(
        hrv: true,
        restingHeartRate: true,
        sleep: true,
        respiratoryRate: false,
      );
      expect(availability.missingSignals, [RecoverySignal.respiratoryRate]);
    });

    test('fully covered has no missing signals', () {
      const availability = RecoverySignalAvailability(
        hrv: true,
        restingHeartRate: true,
        sleep: true,
        respiratoryRate: true,
      );
      expect(availability.missingSignals, isEmpty);
      expect(availability.hasAllSignals, isTrue);
    });
  });

  group('RecoverySignalPrompt', () {
    Future<void> pump(
      WidgetTester tester,
      RecoverySignalAvailability availability,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecoverySignalPrompt(availability: availability),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('hidden when no signals are flowing at all', (tester) async {
      await pump(tester, RecoverySignalAvailability.empty);
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining('Turn it on'), findsNothing);
    });

    testWidgets('hidden when every signal is flowing', (tester) async {
      await pump(
        tester,
        const RecoverySignalAvailability(
          hrv: true,
          restingHeartRate: true,
          sleep: true,
          respiratoryRate: true,
        ),
      );
      expect(find.textContaining('Turn it on'), findsNothing);
    });

    testWidgets('names the specific missing signal, not a generic reconnect', (
      tester,
    ) async {
      await pump(
        tester,
        const RecoverySignalAvailability(
          hrv: false,
          restingHeartRate: true,
          sleep: true,
        ),
      );
      expect(find.textContaining('heart rate variability'), findsOneWidget);
      // Kind, non-generic: it should not say "reconnect".
      expect(find.textContaining('reconnect'), findsNothing);
    });
  });

  group('ConnectHealthPage capability states', () {
    testWidgets('Android needs-install routes to Get Health Connect', (
      tester,
    ) async {
      var installTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: ConnectHealthPage(
              onConnectPressed: () {},
              showPermissionInstructions: false,
              providerAvailability: HealthProviderAvailability.needsInstall,
              onInstallHealthConnect: () => installTapped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Get Health Connect'), findsOneWidget);
      expect(find.text('Set up Health Connect'), findsOneWidget);

      await tester.ensureVisible(find.text('Get Health Connect'));
      await tester.pump();
      await tester.tap(find.text('Get Health Connect'));
      expect(installTapped, isTrue);
    });

    testWidgets('default connect state is unchanged (Connect now CTA)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: ConnectHealthPage(
              onConnectPressed: () {},
              showPermissionInstructions: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Connect now'), findsOneWidget);
      expect(find.text('Get Health Connect'), findsNothing);
    });

    testWidgets('connected-but-missing-signals shows a targeted prompt', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: ConnectHealthPage(
              onConnectPressed: () {},
              showPermissionInstructions: false,
              missingSignals: const [RecoverySignal.hrv],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('heart rate variability'), findsOneWidget);
      expect(find.text('Turn on these signals'), findsOneWidget);
    });
  });
}
