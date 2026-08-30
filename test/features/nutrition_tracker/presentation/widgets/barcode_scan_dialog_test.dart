import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/barcode_scan_dialog.dart';

/// Pumps [BarcodeScanDialog] behind a GoRouter so `context.pop` works, with the
/// camera preview replaced by a tappable stub that fires [onDetect].
Future<void Function(BarcodeCapture)?> _pumpDialog(
  WidgetTester tester, {
  required void Function(Object? result) onClosed,
  MobileScannerException? simulatedError,
}) async {
  void Function(BarcodeCapture)? captured;

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => NoTransitionPage(
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<Object?>(
                      context: context,
                      builder: (_) => BarcodeScanDialog(
                        previewBuilder: (onDetect) {
                          captured = onDetect;
                          return const ColoredBox(color: Colors.black);
                        },
                        simulatedError: simulatedError,
                      ),
                    );
                    onClosed(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('open'));
  await tester.pump();
  return captured;
}

BarcodeCapture _capture(String value) {
  return BarcodeCapture(barcodes: [Barcode(rawValue: value)]);
}

void main() {
  testWidgets('renders the center crosshair viewfinder and guidance', (
    tester,
  ) async {
    await _pumpDialog(tester, onClosed: (_) {});

    expect(find.text('Align the barcode within the frame'), findsOneWidget);
    // Crosshair frame: rounded outline + a horizontal and a vertical reticle.
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('successful detect shows the flash cue and pops the barcode', (
    tester,
  ) async {
    Object? result;
    var closedCalls = 0;
    final onDetect = await _pumpDialog(
      tester,
      onClosed: (value) {
        result = value;
        closedCalls++;
      },
    );

    onDetect!(_capture('  012345678905  '));
    await tester.pump();

    // The success flash overlay is shown before the dialog tears down.
    expect(find.byType(ColoredBox), findsWidgets);

    await tester.pumpAndSettle();
    expect(result, isA<BarcodeScanCode>());
    expect((result as BarcodeScanCode).code, '012345678905');
    expect(closedCalls, 1);
  });

  testWidgets('ignores empty / blank barcodes', (tester) async {
    Object? result;
    var closedCalls = 0;
    final onDetect = await _pumpDialog(
      tester,
      onClosed: (value) {
        result = value;
        closedCalls++;
      },
    );

    onDetect!(_capture('   '));
    await tester.pump();

    expect(closedCalls, 0);
    expect(find.text('Align the barcode within the frame'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('inactivity timeout shows honest actions and never auto-closes', (
    tester,
  ) async {
    Object? result = 'sentinel';
    var closedCalls = 0;
    await _pumpDialog(
      tester,
      onClosed: (value) {
        result = value;
        closedCalls++;
      },
    );

    // Not yet timed out (inactivity window is ~9s).
    await tester.pump(const Duration(milliseconds: 8500));
    expect(find.text('Align the barcode within the frame'), findsOneWidget);
    expect(closedCalls, 0);

    // Cross the inactivity window: the scanner is honest that nothing has
    // been found and offers real actions instead of auto-closing.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('No barcode found yet.'), findsOneWidget);
    expect(find.text('Keep scanning'), findsOneWidget);
    expect(find.text('Enter code manually'), findsOneWidget);
    expect(closedCalls, 0);

    // The dialog must never auto-close out from under the user.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(closedCalls, 0);
    expect(result, 'sentinel');
  });

  testWidgets('tapping keep scanning re-arms the inactivity timer', (
    tester,
  ) async {
    var closedCalls = 0;
    await _pumpDialog(tester, onClosed: (_) => closedCalls++);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('No barcode found yet.'), findsOneWidget);

    await tester.tap(find.text('Keep scanning'));
    await tester.pump();
    expect(find.text('Align the barcode within the frame'), findsOneWidget);
    expect(find.text('No barcode found yet.'), findsNothing);
    expect(closedCalls, 0);

    // The timeout can fire again after another full window.
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('No barcode found yet.'), findsOneWidget);
    expect(closedCalls, 0);
  });

  testWidgets(
    'tapping enter code manually from the timeout pops manual entry',
    (tester) async {
      Object? result;
      var closedCalls = 0;
      await _pumpDialog(
        tester,
        onClosed: (value) {
          result = value;
          closedCalls++;
        },
      );

      await tester.pump(const Duration(seconds: 9));
      await tester.tap(find.text('Enter code manually'));
      await tester.pumpAndSettle();

      expect(result, isA<BarcodeScanManualEntry>());
      expect(closedCalls, 1);
    },
  );

  testWidgets('detect before timeout cancels the auto-dismiss', (tester) async {
    Object? result;
    var closedCalls = 0;
    final onDetect = await _pumpDialog(
      tester,
      onClosed: (value) {
        result = value;
        closedCalls++;
      },
    );

    onDetect!(_capture('5901234123457'));
    await tester.pumpAndSettle();
    expect(result, isA<BarcodeScanCode>());
    expect((result as BarcodeScanCode).code, '5901234123457');
    expect(closedCalls, 1);

    // Pump well past the inactivity window — no second pop should fire.
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(closedCalls, 1);
  });

  testWidgets(
    'permission-denied camera error shows the recovery panel with open '
    'settings',
    (tester) async {
      Object? result;
      var closedCalls = 0;
      await _pumpDialog(
        tester,
        onClosed: (value) {
          result = value;
          closedCalls++;
        },
        simulatedError: const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
        ),
      );

      expect(find.text('Camera access is off'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Enter code manually'), findsOneWidget);

      await tester.tap(find.text('Enter code manually'));
      await tester.pumpAndSettle();

      expect(result, isA<BarcodeScanManualEntry>());
      expect(closedCalls, 1);
    },
  );

  testWidgets(
    'generic camera error shows the recovery panel without open settings',
    (tester) async {
      await _pumpDialog(
        tester,
        onClosed: (_) {},
        simulatedError: const MobileScannerException(
          errorCode: MobileScannerErrorCode.genericError,
        ),
      );

      expect(find.text('Camera unavailable'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
      expect(find.text('Enter code manually'), findsOneWidget);
    },
  );
}
