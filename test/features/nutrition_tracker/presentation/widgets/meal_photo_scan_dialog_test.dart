import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/models/meal_scan_result.dart';
import 'package:hustl_app/features/nutrition_tracker/domain/repositories/meal_scan_repository.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/meal_photo_scan_dialog.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/meal_photo_scan_loading_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake repository whose estimate never resolves, so the dialog stays in its
/// busy state for the duration of the test.
class _NeverEndingMealScanRepository implements MealScanRepository {
  final Completer<MealScanResult> _describe = Completer<MealScanResult>();
  int describeCalls = 0;

  @override
  Future<MealScanResult> describeMeal({
    required String text,
    String? notes,
    String? restaurant,
    String? locale,
  }) {
    describeCalls++;
    return _describe.future;
  }

  @override
  Future<MealScanResult> scanMealPhoto({
    required Uint8List imageBytes,
    required String mimeType,
    String? notes,
    String? restaurant,
    String? locale,
  }) {
    return Completer<MealScanResult>().future;
  }
}

/// 1x1 transparent PNG — a valid image for the photo-path regression test.
Uint8List _tinyPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    await getIt.reset();
  });

  group('describe-a-meal loading', () {
    Future<void> registerDeps(_NeverEndingMealScanRepository repo) async {
      SharedPreferences.setMockInitialValues({'ai_capture_consent': true});
      final prefs = PreferencesService();
      await prefs.init();
      getIt.registerSingleton<PreferencesService>(prefs);
      getIt.registerSingleton<MealScanRepository>(repo);
    }

    GoRouter buildRouter() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/scan'),
                child: const Text('open scan'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scan',
          pageBuilder: (context, state) => NoTransitionPage(
            child: MealPhotoScanDialog(
              date: DateTime(2026, 7, 5),
              primaryAction: MealPhotoScanAction.logMeal,
              autoStartCamera: false,
              startInDescribe: true,
            ),
          ),
        ),
      ],
    );

    /// Drives the describe field to an in-flight estimate and returns once the
    /// dialog has flipped into its busy state. Avoids pumpAndSettle because the
    /// loading view runs continuous animations/timers that never settle.
    Future<void> enterBusy(WidgetTester tester) async {
      await tester.tap(find.text('open scan'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Describe your meal'),
        'grilled chicken with rice',
      );
      await tester.pump();
      await tester.tap(find.text('Estimate'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('busy state renders the loading view, not a bare spinner', (
      tester,
    ) async {
      final repo = _NeverEndingMealScanRepository();
      await registerDeps(repo);

      await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
      await enterBusy(tester);

      expect(repo.describeCalls, 1);
      // The rich loading view replaces the old centered CircularProgressIndicator.
      expect(find.byType(MealPhotoScanLoadingView), findsOneWidget);
      expect(find.text('Estimating your meal…'), findsOneWidget);
      // First rotating hint is shown.
      expect(find.text('Estimating calories & macros'), findsOneWidget);
      // In-context cancel affordance is present.
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Cancel dismisses the dialog', (tester) async {
      await registerDeps(_NeverEndingMealScanRepository());

      await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
      await enterBusy(tester);

      expect(find.byType(MealPhotoScanLoadingView), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Back on the home route; the loading view is gone.
      expect(find.byType(MealPhotoScanLoadingView), findsNothing);
      expect(find.text('open scan'), findsOneWidget);
    });
  });

  group('MealPhotoScanLoadingView', () {
    Future<void> pumpView(
      WidgetTester tester, {
      required Uint8List? imageBytes,
      String hintText = 'Breaking into items',
      bool isTakingLong = false,
      VoidCallback? onCancel,
      VoidCallback? onLogManuallyInstead,
      bool showItemsSkeleton = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MealPhotoScanLoadingView(
                imageBytes: imageBytes,
                hintText: hintText,
                isTakingLong: isTakingLong,
                onCancel: onCancel ?? () {},
                onLogManuallyInstead: onLogManuallyInstead,
                showItemsSkeleton: showItemsSkeleton,
              ),
            ),
          ),
        ),
      );
      // Single pump only — the view animates continuously and never settles.
      await tester.pump();
    }

    testWidgets('text-only mode renders hints and skeleton without a photo', (
      tester,
    ) async {
      await pumpView(tester, imageBytes: null, hintText: 'Breaking into items');

      expect(find.text('Estimating your meal…'), findsOneWidget);
      expect(find.text('Breaking into items'), findsOneWidget);
      // No photo header in text-only mode.
      expect(find.byType(Image), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      // Item skeleton section is present.
      expect(find.text('Items'), findsOneWidget);
    });

    testWidgets(
      'text-only taking-long shows reassurance and log-manually escape hatch',
      (tester) async {
        await pumpView(
          tester,
          imageBytes: null,
          hintText: 'Almost done',
          isTakingLong: true,
          onLogManuallyInstead: () {},
        );

        expect(find.text('Still working—network may be slow.'), findsOneWidget);
        expect(
          find.widgetWithText(TextButton, 'Log manually instead'),
          findsOneWidget,
        );
      },
    );

    testWidgets('text-only Cancel invokes the callback', (tester) async {
      var cancelled = false;
      await pumpView(
        tester,
        imageBytes: null,
        onCancel: () => cancelled = true,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      expect(cancelled, isTrue);
    });

    testWidgets('photo mode still renders the photo header (regression)', (
      tester,
    ) async {
      await pumpView(tester, imageBytes: _tinyPng(), hintText: 'Almost done');

      // Photo header is present with the photo-specific copy.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Scanning your meal…'), findsOneWidget);
      expect(find.text('Estimating your meal…'), findsNothing);
    });
  });
}
