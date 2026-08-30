import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hustl_app/core/services/analytics_service.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/onboarding/domain/onboarding_telemetry.dart';

class _RecordingSink implements TelemetrySink {
  final List<TelemetryEvent> events = [];

  @override
  void add(TelemetryEvent event) => events.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingSink sink;
  late OnboardingTelemetry telemetry;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    prefs.resetForTests();
    await prefs.init();
    sink = _RecordingSink();
    telemetry = OnboardingTelemetry(
      AnalyticsService(preferences: prefs, sink: sink),
    );
  });

  test('welcomeShown emits the welcome event with no props', () {
    telemetry.welcomeShown();
    expect(sink.events.single.name, 'onboarding_welcome_shown');
    expect(sink.events.single.props, isEmpty);
  });

  test('welcomeAction carries the action token', () {
    telemetry.welcomeAction('start');
    expect(sink.events.single.name, 'onboarding_welcome_action');
    expect(sink.events.single.props, {'action': 'start'});
  });

  test('importCompleted carries the real workout count', () {
    telemetry.importCompleted(workouts: 42);
    expect(sink.events.single.name, 'onboarding_import_completed');
    expect(sink.events.single.props, {'workouts': 42});
  });

  test('healthPrimerResult carries the result token', () {
    telemetry.healthPrimerResult('connect');
    expect(sink.events.single.name, 'onboarding_health_primer_result');
    expect(sink.events.single.props, {'result': 'connect'});
  });

  test('migration + cursor-reset events carry kind/scope', () {
    telemetry.migrationApplied('guestUpgrade');
    telemetry.syncCursorReset('workoutsAndTemplates');

    expect(sink.events[0].name, 'onboarding_migration_applied');
    expect(sink.events[0].props, {'kind': 'guestUpgrade'});
    expect(sink.events[1].name, 'onboarding_sync_cursor_reset');
    expect(sink.events[1].props, {'scope': 'workoutsAndTemplates'});
  });

  test('remaining funnel methods emit their stable names', () {
    telemetry.firstWinShown();
    telemetry.proposalShown();
    telemetry.proposalApproved();
    telemetry.upgradePromptShown();
    telemetry.upgradeLinked();

    expect(sink.events.map((e) => e.name).toList(), <String>[
      'onboarding_first_win_shown',
      'onboarding_proposal_shown',
      'onboarding_proposal_approved',
      'onboarding_upgrade_prompt_shown',
      'onboarding_upgrade_linked',
    ]);
  });

  test('disabled() instance is a safe no-op', () {
    expect(
      () => OnboardingTelemetry.disabled().welcomeShown(),
      returnsNormally,
    );
  });
}
