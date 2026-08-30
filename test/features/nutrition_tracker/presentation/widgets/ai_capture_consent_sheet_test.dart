import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/ai_capture_consent_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    if (GetIt.instance.isRegistered<PreferencesService>()) {
      await GetIt.instance.unregister<PreferencesService>();
    }
  });

  tearDown(() async {
    if (GetIt.instance.isRegistered<PreferencesService>()) {
      await GetIt.instance.unregister<PreferencesService>();
    }
  });

  testWidgets(
    'ensureAiCaptureConsent returns true immediately when consent is set',
    (tester) async {
      // Seed the pref so the gate should short-circuit with no UI.
      SharedPreferences.setMockInitialValues({'ai_capture_consent': true});
      final prefs = PreferencesService();
      await prefs.init();
      GetIt.instance.registerSingleton<PreferencesService>(prefs);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await ensureAiCaptureConsent(context);
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      // No bottom sheet was shown — the gate resolved from the stored pref.
      expect(find.text('Use AI to estimate macros?'), findsNothing);
    },
  );
}
