import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_theme.dart';
import 'package:hustl_app/features/health_sync/presentation/widgets/health_overview_header.dart';

void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required ThemeData theme,
    required HealthSyncHeaderStatus status,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: HealthScreenHeader(status: status)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color dotColor(WidgetTester tester) {
    final dot = tester.widget<Container>(
      find.byKey(const Key('health-sync-status-dot')),
    );
    return (dot.decoration! as BoxDecoration).color!;
  }

  Color labelColor(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label)).style!.color!;
  }

  testWidgets('live status keeps semantic color on the dot only', (
    tester,
  ) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await pumpHeader(
        tester,
        theme: theme,
        status: HealthSyncHeaderStatus.live,
      );
      final renderedTheme = Theme.of(
        tester.element(find.byType(HealthScreenHeader)),
      );

      expect(dotColor(tester), AppColors.accentEmeraldGreen);
      expect(
        labelColor(tester, 'Live health sync'),
        renderedTheme.colorScheme.onSurface,
      );
    }
  });

  testWidgets('failure status keeps semantic color on the dot only', (
    tester,
  ) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await pumpHeader(
        tester,
        theme: theme,
        status: HealthSyncHeaderStatus.unavailable,
      );
      final renderedTheme = Theme.of(
        tester.element(find.byType(HealthScreenHeader)),
      );

      expect(dotColor(tester), renderedTheme.colorScheme.error);
      expect(
        labelColor(tester, 'Health sync unavailable'),
        renderedTheme.colorScheme.onSurface,
      );
    }
  });
}
