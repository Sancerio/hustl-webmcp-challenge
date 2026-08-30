import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/app/theme/app_theme.dart';

/// Guards the button typography fix: ButtonStyle.textStyle replaces the
/// theme textTheme style, so without an explicit family every button label
/// rendered in the platform default font (tofu in test dumps) instead of
/// DM Sans. Run with `--update-goldens` to refresh goldens/.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Load every bundled font from the generated manifest (DM Sans + the
    // framework's MaterialIcons) so text renders as on device.
    final manifest =
        json.decode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String;
      final loader = FontLoader(family);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  Widget buttonColumn() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: () {}, child: const Text('Filled button')),
          const SizedBox(height: AppSpacing.x2),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Elevated button'),
          ),
          const SizedBox(height: AppSpacing.x2),
          OutlinedButton(
            onPressed: () {},
            child: const Text('Outlined button'),
          ),
          const SizedBox(height: AppSpacing.x2),
          TextButton(onPressed: () {}, child: const Text('Text button')),
          const SizedBox(height: AppSpacing.x2),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Week')),
              ButtonSegment(value: 1, label: Text('Month')),
              ButtonSegment(value: 2, label: Text('Year')),
            ],
            selected: const {0},
            onSelectionChanged: (_) {},
          ),
        ],
      ),
    );
  }

  Future<void> pumpButtons(WidgetTester tester, ThemeData theme) async {
    tester.view.devicePixelRatio = 2.0;
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(body: SafeArea(child: buttonColumn())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('button labels render DM Sans (light)', (tester) async {
    await pumpButtons(tester, AppTheme.lightTheme);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/button_typography_light.png'),
    );
  });

  testWidgets('button labels render DM Sans (dark)', (tester) async {
    await pumpButtons(tester, AppTheme.darkTheme);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/button_typography_dark.png'),
    );
  });
}
