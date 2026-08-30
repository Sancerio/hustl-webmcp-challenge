import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/watch_recording_card.dart';
import 'package:hustl_app/features/workout_logging/presentation/widgets/watch_recording_medallion.dart';

/// Mounts the card with the real app theme. [disableAnimations] drives the
/// reduced-motion path; the harness never reuses a controller between pumps.
Widget _host({
  required bool isRecording,
  required bool isRequested,
  bool disableAnimations = false,
  VoidCallback? onRequestStart,
  VoidCallback? onRequestCancel,
  VoidCallback? onRequestStop,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: disableAnimations),
            child: Center(
              child: WatchRecordingCard(
                isRecording: isRecording,
                isRequested: isRequested,
                onRequestStart: onRequestStart ?? () {},
                onRequestCancel: onRequestCancel ?? () {},
                onRequestStop: onRequestStop ?? () {},
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Mounts the card under a [ValueListenableBuilder] so a test can flip
/// `isRecording` (and optionally `isRequested`) mid-flight, mirroring the
/// parent driving the watch bridge.
Widget _drivenHost({
  required ValueListenable<bool> recording,
  bool Function(bool recording)? requested,
  bool disableAnimations = false,
  VoidCallback? onRequestStart,
  VoidCallback? onRequestStop,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: disableAnimations),
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: recording,
                builder: (_, isRecording, __) => WatchRecordingCard(
                  isRecording: isRecording,
                  isRequested:
                      requested?.call(isRecording) ?? !isRecording,
                  onRequestStart: onRequestStart ?? () {},
                  onRequestCancel: () {},
                  onRequestStop: onRequestStop ?? () {},
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// The current sonar [SonarPainter.phase] rendered by the medallion, or null if
/// the rings aren't being painted.
double? _currentSonarPhase(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<SonarPainter>();
  return paints.isEmpty ? null : paints.first.phase;
}

void main() {
  testWidgets('searching renders sonar copy with a TextButton cancel and a '
      'tonal send again — not two Expanded halves', (tester) async {
    await tester.pumpWidget(
      _host(isRecording: false, isRequested: true, disableAnimations: true),
    );
    await tester.pump();

    expect(find.text('Looking for your watch'), findsOneWidget);
    expect(
      find.text('Open Hustl on your Apple Watch to start.'),
      findsOneWidget,
    );

    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send again'), findsOneWidget);
    // Sized-to-content row, never two Expanded halves.
    expect(find.byType(Expanded), findsNothing);
  });

  testWidgets('tapping send again calls onRequestStart and flips the subtitle '
      'to "Sending again…"', (tester) async {
    var starts = 0;
    await tester.pumpWidget(
      _host(
        isRecording: false,
        isRequested: true,
        disableAnimations: true,
        onRequestStart: () => starts++,
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Send again'));
    await tester.pump();

    expect(starts, 1);
    expect(find.text('Sending again…'), findsOneWidget);
  });

  testWidgets('watchdog promotes to not-found copy with a solid FilledButton '
      'send again after ~22s', (tester) async {
    await tester.pumpWidget(
      _host(isRecording: false, isRequested: true, disableAnimations: true),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 23));
    // Let the AnimatedSwitcher finish swapping out the searching child.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("We couldn't reach your watch"), findsOneWidget);
    expect(
      find.text(
        'Open Hustl on your watch, then send again — or keep logging here.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    // Promoted: a solid FilledButton (not the .tonal variant) labelled
    // "Send again". The tonal builder produces a FilledButton too, so we assert
    // the label is present on a FilledButton and the not-found copy is showing.
    expect(find.widgetWithText(FilledButton, 'Send again'), findsOneWidget);
  });

  testWidgets('flipping isRecording true shows Connected then Recording on '
      'Apple Watch', (tester) async {
    final start = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(disableAnimations: true),
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: start,
                    builder: (_, recording, __) => WatchRecordingCard(
                      isRecording: recording,
                      isRequested: !recording,
                      onRequestStart: () {},
                      onRequestCancel: () {},
                      onRequestStop: () {},
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Looking for your watch'), findsOneWidget);

    start.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Recording on Apple Watch.'), findsOneWidget);

    // After the connected hold, settle into the sustained recording state.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Recording on Apple Watch'), findsOneWidget);
    expect(
      find.text('Heart rate and energy will be saved with this workout.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Stop recording'),
      findsOneWidget,
    );
  });

  testWidgets('reduce-motion renders with no running controller (no pending '
      'timer failures on settle)', (tester) async {
    await tester.pumpWidget(
      _host(isRecording: false, isRequested: false, disableAnimations: true),
    );
    // pumpAndSettle would hang on a repeating controller; in reduced motion the
    // controller never repeats, so this resolves cleanly.
    await tester.pumpAndSettle();

    expect(
      find.text('Track heart rate and energy on your wrist.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsOneWidget,
    );
  });

  testWidgets('sonar rings animate: SonarPainter.phase changes across pumps '
      '(not frozen) while searching', (tester) async {
    // Motion enabled so the controller actually repeats and drives the rings.
    await tester.pumpWidget(
      _host(isRecording: false, isRequested: true),
    );
    await tester.pump();

    // Rings are being painted in the searching state.
    final first = _currentSonarPhase(tester);
    expect(first, isNotNull);

    // Advance the controller a few frames; the live phase must move, proving
    // the medallion is rebuilt with the current controller value each tick
    // rather than capturing one value as a static AnimatedBuilder child.
    final seen = <double>{first!};
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      final phase = _currentSonarPhase(tester);
      expect(phase, isNotNull);
      seen.add(phase!);
    }
    expect(
      seen.length,
      greaterThan(1),
      reason: 'sonar phase should change frame to frame, not stay frozen',
    );

    // Stop the repeating controller so the test can settle cleanly.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('reduce-motion keeps the sonar phase frozen at 0 (no animation)',
      (tester) async {
    await tester.pumpWidget(
      _host(isRecording: false, isRequested: true, disableAnimations: true),
    );
    await tester.pump();

    expect(_currentSonarPhase(tester), 0.0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_currentSonarPhase(tester), 0.0);
  });

  testWidgets('tapping Stop enters a stopping state, keeps the recording UI '
      'disabled, and cannot fire another start while isRecording stays true',
      (tester) async {
    final recording = ValueNotifier<bool>(true);
    var stops = 0;
    var starts = 0;
    await tester.pumpWidget(
      _drivenHost(
        recording: recording,
        // While recording the parent keeps isRequested false.
        requested: (_) => false,
        disableAnimations: true,
        onRequestStart: () => starts++,
        onRequestStop: () => stops++,
      ),
    );
    // Settle into the sustained recording state (connected hold elapses).
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.widgetWithText(OutlinedButton, 'Stop recording'), findsOneWidget);

    // Tap Stop: requests the stop and enters the in-flight stopping state.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop recording'));
    await tester.pump();
    expect(stops, 1);
    // Both the card title and the disabled button read "Stopping…".
    expect(find.text('Stopping…'), findsWidgets);
    expect(
      find.widgetWithText(OutlinedButton, 'Stopping…'),
      findsOneWidget,
    );

    // Must NOT fall back to the start UI while isRecording is still true.
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsNothing,
    );
    expect(
      find.text('Track heart rate and energy on your wrist.'),
      findsNothing,
    );

    // The stopping control is disabled — no stray start/stop can fire.
    final stopping = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Stopping…'),
    );
    expect(stopping.onPressed, isNull);
    expect(starts, 0);

    // Parent still reports recording: stay in stopping (don't go idle).
    await tester.pump(const Duration(seconds: 1));
    expect(find.widgetWithText(OutlinedButton, 'Stopping…'), findsOneWidget);

    // Only once isRecording actually drops to false do we settle to idle/start.
    recording.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Stopping…'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsOneWidget,
    );
    expect(starts, 0);
  });

  testWidgets('parent flipping isRequested false -> true (no tap) enters the '
      'searching UI and arms the watchdog -> not-found after ~22s',
      (tester) async {
    final requested = ValueNotifier<bool>(false);
    var starts = 0;
    addTearDown(requested.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(disableAnimations: true),
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: requested,
                    builder: (_, isRequested, __) => WatchRecordingCard(
                      isRecording: false,
                      isRequested: isRequested,
                      // The parent drives the request; our button is never
                      // tapped, so onRequestStart must NOT fire on the resync.
                      onRequestStart: () => starts++,
                      onRequestCancel: () {},
                      onRequestStop: () {},
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // Starts idle: the resting "Record on Apple Watch" invitation.
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsOneWidget,
    );

    // Parent starts requesting watch recording from elsewhere (no tap on us).
    requested.value = true;
    await tester.pump();
    // Let the AnimatedSwitcher swap idle -> searching.
    await tester.pump(const Duration(milliseconds: 400));

    // We resync into the searching story with Cancel + Send again.
    expect(find.text('Looking for your watch'), findsOneWidget);
    expect(
      find.text('Open Hustl on your Apple Watch to start.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send again'), findsOneWidget);
    // The card never invented a start: the request rose from the parent.
    expect(starts, 0);

    // The watchdog armed on resync fires after ~22s -> blame-free not-found.
    await tester.pump(const Duration(seconds: 23));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("We couldn't reach your watch"), findsOneWidget);
    expect(starts, 0);
  });

  testWidgets('stop watchdog recovers to a live Stop when isRecording stays '
      'true past the grace window (lost stop can be retried)', (tester) async {
    final recording = ValueNotifier<bool>(true);
    addTearDown(recording.dispose);
    var stops = 0;
    await tester.pumpWidget(
      _drivenHost(
        recording: recording,
        requested: (_) => false,
        disableAnimations: true,
        onRequestStop: () => stops++,
      ),
    );
    // Settle into the sustained recording state.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      find.widgetWithText(OutlinedButton, 'Stop recording'),
      findsOneWidget,
    );

    // Tap Stop: enters the in-flight stopping state with a disabled control.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop recording'));
    await tester.pump();
    expect(stops, 1);
    final stopping = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Stopping…'),
    );
    expect(stopping.onPressed, isNull);

    // The parent never confirms the stop (request lost): isRecording stays true
    // past the watchdog. We must recover instead of sitting on "Stopping…".
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 400));

    // Stop is live again so the lost stop can be retried.
    expect(find.text('Stopping…'), findsNothing);
    final liveStop = find.widgetWithText(OutlinedButton, 'Stop recording');
    expect(liveStop, findsOneWidget);
    expect(tester.widget<OutlinedButton>(liveStop).onPressed, isNotNull);

    // Re-tapping the recovered Stop re-sends onRequestStop.
    await tester.tap(liveStop);
    await tester.pump();
    expect(stops, 2);
    expect(find.widgetWithText(OutlinedButton, 'Stopping…'), findsOneWidget);
  });

  testWidgets('stopping settles to idle on isRecording=false before the '
      'watchdog fires (normal path, no recovery flash)', (tester) async {
    final recording = ValueNotifier<bool>(true);
    addTearDown(recording.dispose);
    await tester.pumpWidget(
      _drivenHost(
        recording: recording,
        requested: (_) => false,
        disableAnimations: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));

    // Tap Stop -> stopping.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop recording'));
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'Stopping…'), findsOneWidget);

    // The stop confirms (isRecording drops) well before the watchdog grace
    // window: settle to idle via the normal path, never bouncing to recording.
    await tester.pump(const Duration(seconds: 1));
    recording.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Stopping…'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsOneWidget,
    );

    // Past the original watchdog window: a cancelled timer must not resurrect a
    // recording/stop UI on the idle card.
    await tester.pump(const Duration(seconds: 10));
    expect(
      find.widgetWithText(OutlinedButton, 'Stop recording'),
      findsNothing,
    );
    expect(find.text('Stopping…'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsOneWidget,
    );
  });
  testWidgets('two-action row stays overflow-safe at 320px with TextScaler 2.0 '
      '(Cancel + Send again remain present and hittable)', (tester) async {
    // Force a narrow (320px) phone with large accessibility text. The two-action
    // row must wrap rather than throw a RenderFlex overflow that clips the retry
    // controls.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: Center(
                  child: WatchRecordingCard(
                    isRecording: false,
                    isRequested: true,
                    onRequestStart: () {},
                    onRequestCancel: () {},
                    onRequestStop: () {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // No RenderFlex overflow (or any other) exception was thrown during layout.
    expect(tester.takeException(), isNull);

    // Both actions are present...
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    final sendAgain = find.widgetWithText(FilledButton, 'Send again');
    expect(cancel, findsOneWidget);
    expect(sendAgain, findsOneWidget);

    // ...and fully usable: tapping each still fires without an off-screen hit.
    await tester.tap(cancel, warnIfMissed: false);
    await tester.pump();
    // Cancel returned the card to its resting idle invitation.
    expect(
      find.widgetWithText(FilledButton, 'Record on Apple Watch'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounting straight into searching (isRequested: true) then an '
      'instant isRecording: true takes the FAST sub-second skip, not the full '
      '900ms hold — _searchingSince was seeded on mount', (tester) async {
    // A default-enabled session seeds watchRecordingRequested: true, so the card
    // mounts directly into the searching story without a Record press. An
    // instant connect from this mounted-searching start must still take the
    // sub-second fast-skip (~400ms) — proving initState stamped _searchingSince.
    final recording = ValueNotifier<bool>(false);
    addTearDown(recording.dispose);
    await tester.pumpWidget(
      _drivenHost(
        recording: recording,
        // Mounts into searching (isRequested true while not recording), then
        // stays requested-false once recording flips on.
        requested: (isRecording) => !isRecording,
        disableAnimations: true,
      ),
    );
    await tester.pump();
    // Confirms the mounted-into-searching start (no Record press happened).
    expect(find.text('Looking for your watch'), findsOneWidget);

    // Instant connect on the very next frame: an immediate isRecording: true.
    recording.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);

    // FAST path discriminator: at 700ms we are past the sub-second skip (400ms)
    // but still well before the full connected hold (900ms). The sustained
    // recording copy is therefore already showing. With a null _searchingSince
    // (the bug) fast would be forced false and we'd still be on the 'Connected'
    // hold here — the recording subtitle would NOT yet be present.
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.text('Recording on Apple Watch'),
      findsOneWidget,
    );
    expect(
      find.text('Heart rate and energy will be saved with this workout.'),
      findsOneWidget,
    );

    // Let the switcher finish fading the transient connected child out, then
    // confirm we settled cleanly on recording (no stuck 'Connected').
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Recording on Apple Watch'), findsOneWidget);
  });
}
