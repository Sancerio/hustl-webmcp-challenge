import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_text_styles.dart';
import 'package:hustl_app/app/theme/app_theme.dart';

void main() {
  test('text theme resolves to the bundled DM Sans family', () {
    final theme = AppTheme.darkTheme;
    final text = theme.textTheme;

    expect(AppTextStyles.fontFamily, 'DM Sans');
    expect(text.bodyMedium?.fontFamily, 'DM Sans');
    expect(text.titleLarge?.fontFamily, 'DM Sans');
    expect(text.displayLarge?.fontFamily, 'DM Sans');
  });

  test('button and segmented-button labels carry DM Sans', () {
    // ButtonStyle.textStyle REPLACES the theme textTheme style, so each
    // button theme must pin the family itself or labels render in the
    // platform default font.
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final buttonStyles = <TextStyle?>[
        theme.textButtonTheme.style?.textStyle?.resolve(const {}),
        theme.filledButtonTheme.style?.textStyle?.resolve(const {}),
        theme.outlinedButtonTheme.style?.textStyle?.resolve(const {}),
        theme.elevatedButtonTheme.style?.textStyle?.resolve(const {}),
        theme.segmentedButtonTheme.style?.textStyle?.resolve(const {}),
        theme.segmentedButtonTheme.style?.textStyle?.resolve(const {
          WidgetState.selected,
        }),
        theme.chipTheme.labelStyle,
      ];
      for (final style in buttonStyles) {
        expect(style?.fontFamily, AppTextStyles.fontFamily);
        expect(style?.fontFamilyFallback, AppTextStyles.fontFallback);
      }
    }
  });

  test('the §12.1 hard scale is pinned', () {
    final text = AppTheme.darkTheme.textTheme;

    // Screen / app-bar title: 20/w700.
    expect(text.titleLarge?.fontSize, 20);
    expect(text.titleLarge?.fontWeight, FontWeight.w700);

    // Row label: 15/w500; reading voice 15/w400.
    expect(text.bodyLarge?.fontSize, 15);
    expect(text.bodyLarge?.fontWeight, FontWeight.w500);
    expect(text.bodyMedium?.fontSize, 15);
    expect(text.bodyMedium?.fontWeight, FontWeight.w400);

    // Row value: 15/w600 tabular.
    expect(text.labelLarge?.fontSize, 15);
    expect(text.labelLarge?.fontWeight, FontWeight.w600);
    expect(
      text.labelLarge?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    // Caption / units: 12/w400.
    expect(text.bodySmall?.fontSize, 12);
    expect(text.bodySmall?.fontWeight, FontWeight.w400);

    // Section-header voice on titleSmall: 13/w600 +0.6.
    expect(text.titleSmall?.fontSize, 13);
    expect(text.titleSmall?.fontWeight, FontWeight.w600);
    expect(text.titleSmall?.letterSpacing, 0.6);
  });

  test('every headline/display slot except the rest timer caps at 22', () {
    final text = AppTheme.darkTheme.textTheme;

    // Rest-timer tier only.
    expect(text.displayLarge?.fontSize, 56);

    for (final style in [
      text.displayMedium,
      text.displaySmall,
      text.headlineLarge,
      text.headlineMedium,
    ]) {
      expect(style?.fontSize, 22);
      expect(style?.fontWeight, FontWeight.w700);
      expect(style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
    expect(text.headlineSmall?.fontSize, 20);
  });

  test('metric() applies tabular figures', () {
    final styled = AppTextStyles.metric(const TextStyle(fontSize: 24));
    expect(styled.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('sectionHeader helper matches the §12.1 spec', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            style = AppTextStyles.sectionHeader(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontSize, 13);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.letterSpacing, 0.6);
    expect(style.color, AppTheme.lightTheme.colorScheme.onSurfaceVariant);
  });

  testWidgets('metricEmphasis is 22/w700 tabular', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            style = AppTextStyles.metricEmphasis(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontSize, 22);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  test('canvases are cool off-white / near-black with layered surfaces', () {
    expect(
      AppTheme.lightTheme.scaffoldBackgroundColor,
      const Color(0xFFF2F5FA),
    );
    expect(AppTheme.darkTheme.scaffoldBackgroundColor, const Color(0xFF0B0B0F));

    // Layered: cards sit ABOVE the canvas (surface != background).
    expect(AppTheme.lightTheme.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(AppTheme.darkTheme.colorScheme.surface, const Color(0xFF15151F));

    // Raised dark surfaces step up to #1F2230.
    expect(
      AppTheme.darkTheme.colorScheme.surfaceContainerHigh,
      const Color(0xFF1F2230),
    );
  });

  test('cards are rounded with a soft shadow in light, flat in dark', () {
    expect(AppTheme.darkTheme.cardTheme.elevation, 0);
    expect(AppTheme.lightTheme.cardTheme.elevation, 1.5);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.side, BorderSide.none);
    }
  });

  test('dividers are 1px hairlines', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(theme.dividerTheme.thickness, 1);
      expect(theme.dividerTheme.color, theme.colorScheme.outlineVariant);
    }
  });

  test('FAB theme is the flat 56px primary circle', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final fab = theme.floatingActionButtonTheme;
      expect(fab.backgroundColor, theme.colorScheme.primary);
      expect(fab.foregroundColor, theme.colorScheme.onPrimary);
      expect(fab.elevation, 0);
      expect(fab.shape, const CircleBorder());
      expect(
        fab.sizeConstraints,
        const BoxConstraints.tightFor(width: 56, height: 56),
      );
    }
  });

  test('the restored Hustl palette: emerald + electric blue + amber', () {
    expect(AppColors.accentElectricBlue, const Color(0xFF3B82F6));
    expect(AppColors.accentEmeraldGreen, const Color(0xFF10B981));
    expect(AppColors.accentWarningAmber, const Color(0xFFF59E0B));

    // Macro mapping: protein emerald, carbs blue, fat amber.
    expect(AppColors.macroProtein, AppColors.accentEmeraldGreen);
    expect(AppColors.macroCarbs, AppColors.accentElectricBlue);
    expect(AppColors.macroFat, AppColors.accentWarningAmber);

    // Blue is the brand primary in both themes.
    expect(
      AppTheme.lightTheme.colorScheme.primary,
      AppColors.accentElectricBlue,
    );
    expect(
      AppTheme.darkTheme.colorScheme.primary,
      AppColors.accentElectricBlue,
    );
  });

  test('both themes build without throwing', () {
    expect(() => AppTheme.lightTheme, returnsNormally);
    expect(() => AppTheme.darkTheme, returnsNormally);
  });
}
