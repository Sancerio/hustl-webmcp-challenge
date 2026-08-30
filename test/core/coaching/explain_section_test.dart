import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/coaching/explain_section.dart';

// Widget tests for [CoachExplainSection]'s reset behavior (PR #381 Finding 3).
//
// The fix: the section resets the loaded narrative when [resetKey] changes — NOT
// when the [fetchNarrative] CLOSURE identity changes. The call sites pass INLINE
// closures, so an unrelated rebuild recreates the callback every frame; keying the
// reset off closure identity would clear a valid note even though resetKey and the
// explained inputs are unchanged. These tests pin both directions:
//   (1) a rebuild that changes ONLY the closure (same resetKey) does NOT clear the note;
//   (2) a resetKey change DOES clear it;
// plus a regression that the monotonic stale-token guard still discards a fetch
// that resolves after a resetKey change.
void main() {
  // A live host that keeps the SAME State element across rebuilds (so
  // didUpdateWidget fires) while letting the test swap the fetchNarrative closure
  // and the resetKey independently via the builders.
  Future<void Function(void Function())> pumpHost(
    WidgetTester tester, {
    required Future<String?> Function() Function() fetcherBuilder,
    required Object? Function() resetKeyBuilder,
  }) async {
    late void Function(void Function()) hostSetState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              hostSetState = setState;
              return CoachExplainSection(
                fetchNarrative: fetcherBuilder(),
                resetKey: resetKeyBuilder(),
              );
            },
          ),
        ),
      ),
    );
    return hostSetState;
  }

  testWidgets(
    'a rebuild that changes ONLY the fetchNarrative closure (same resetKey) keeps the note',
    (tester) async {
      const noteText = 'Your readiness sits at 78 out of 100.';
      const stableResetKey = 'inputs-v1';

      final hostSetState = await pumpHost(
        tester,
        // A NEW closure instance every build — mirrors an inline call site.
        fetcherBuilder: () => () async => noteText,
        resetKeyBuilder: () => stableResetKey,
      );

      // Fetch + render the note.
      await tester.tap(find.text('Explain my numbers'));
      await tester.pumpAndSettle();
      expect(find.text(noteText), findsOneWidget);
      expect(find.text('Explain my numbers'), findsNothing);

      // Rebuild the host WITHOUT changing resetKey. The fetcherBuilder produces a
      // brand-new closure identity, exactly the unrelated-rebuild scenario.
      hostSetState(() {});
      await tester.pumpAndSettle();

      // The loaded note must SURVIVE — closure identity change alone never resets.
      expect(find.text(noteText), findsOneWidget);
      expect(find.text('Explain my numbers'), findsNothing);
    },
  );

  testWidgets(
    'a resetKey change DOES clear a loaded note and restores the affordance',
    (tester) async {
      const noteText = 'Your readiness sits at 78 out of 100.';
      var resetKey = 'inputs-v1';

      final hostSetState = await pumpHost(
        tester,
        fetcherBuilder: () => () async => noteText,
        resetKeyBuilder: () => resetKey,
      );

      // Fetch + render the note.
      await tester.tap(find.text('Explain my numbers'));
      await tester.pumpAndSettle();
      expect(find.text(noteText), findsOneWidget);

      // Change the explained inputs (resetKey differs).
      hostSetState(() {
        resetKey = 'inputs-v2';
      });
      await tester.pumpAndSettle();

      // The stale note is cleared and the affordance is back.
      expect(find.text(noteText), findsNothing);
      expect(find.text('Explain my numbers'), findsOneWidget);
    },
  );

  testWidgets(
    'a fetch that resolves after a resetKey change is discarded (stale-token guard intact)',
    (tester) async {
      // Hold the fetch open, change resetKey while in flight, then resolve — the
      // late note must not paint over the reset.
      final completer = Completer<String?>();
      var resetKey = 'inputs-v1';

      final hostSetState = await pumpHost(
        tester,
        fetcherBuilder: () => () => completer.future,
        resetKeyBuilder: () => resetKey,
      );

      // Kick off the (pending) explain request.
      await tester.tap(find.text('Explain my numbers'));
      await tester.pump();

      // Change the inputs while the fetch is in flight.
      hostSetState(() {
        resetKey = 'inputs-v2';
      });
      await tester.pump();

      // Resolve the stale fetch AFTER the input change — it must be dropped.
      completer.complete('STALE note for old inputs');
      await tester.pumpAndSettle();

      expect(find.text('STALE note for old inputs'), findsNothing);
      expect(find.text('Explain my numbers'), findsOneWidget);
    },
  );
}
