import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Wave G (MacroFactor fidelity) theme: a stark black-and-white instrument.
/// Pure-white light canvas, true-black dark canvas, borderless flat cards,
/// hairline dividers, blue as the single interactive accent, and a 56px blue
/// '+' FAB pattern that screens attach themselves.
class AppTheme {
  AppTheme._();

  static const BorderRadius _cardRadius = AppRadius.cardRadius;
  static const BorderRadius _controlRadius = AppRadius.controlRadius;
  static const BorderRadius _sheetRadius = AppRadius.sheetRadius;

  // Button label: row-value voice (15/w600). ButtonStyle.textStyle REPLACES
  // the theme textTheme style, so it must carry the DM Sans family itself or
  // button labels fall back to the platform default font.
  static const TextStyle _buttonTextStyle = TextStyle(
    fontFamily: AppTextStyles.fontFamily,
    fontFamilyFallback: AppTextStyles.fontFallback,
    fontWeight: FontWeight.w600,
    fontSize: 15,
  );

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final baseScheme = ColorScheme.light(
      primary: AppColors.primaryLight,
      onPrimary: AppColors.onPrimaryLight,
      primaryContainer: AppColors.primaryContainerLight,
      onPrimaryContainer: AppColors.onPrimaryContainerLight,
      secondary: AppColors.secondaryLight,
      onSecondary: AppColors.onSecondaryLight,
      secondaryContainer: AppColors.secondaryContainerLight,
      onSecondaryContainer: AppColors.onSecondaryContainerLight,
      tertiary: AppColors.tertiaryLight,
      onTertiary: AppColors.onTertiaryLight,
      tertiaryContainer: AppColors.tertiaryContainerLight,
      onTertiaryContainer: AppColors.onTertiaryContainerLight,
      error: AppColors.errorLight,
      onError: AppColors.onErrorLight,
      errorContainer: AppColors.errorContainerLight,
      onErrorContainer: AppColors.onErrorContainerLight,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.onSurfaceLight,
      outline: AppColors.outlineLight,
      outlineVariant: AppColors.outlineVariantLight,
      shadow: AppColors.brandCarbonBlack.withValues(alpha: 0.05),
      scrim: AppColors.brandCarbonBlack,
      surfaceTint: Colors.transparent,
    );
    final colorScheme = baseScheme.copyWith(
      surfaceContainerLowest: AppColors.backgroundLight,
      surfaceContainerLow: AppColors.surfaceLight,
      surfaceContainer: AppColors.surfaceLight,
      surfaceContainerHigh: AppColors.surfaceVariantLight,
      surfaceContainerHighest: AppColors.surfaceVariantLight,
    );
    final textTheme = AppTextStyles.light(base.textTheme, colorScheme);

    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      colorScheme: colorScheme,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: _appBarTheme(textTheme, colorScheme),
      dividerTheme: _dividerTheme(colorScheme),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: _sheetRadius),
      ),
      inputDecorationTheme: _inputDecorationTheme(
        textTheme,
        colorScheme,
        fillColor: colorScheme.surfaceContainerHigh,
      ),
      snackBarTheme: _snackBarTheme(textTheme, colorScheme),
      cardTheme: _cardTheme(colorScheme),
      chipTheme: _chipTheme(base.chipTheme, colorScheme),
      dialogTheme: _dialogTheme(textTheme, colorScheme),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: _buttonTextStyle,
        ),
      ),
      filledButtonTheme: _filledButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      floatingActionButtonTheme: _fabTheme(colorScheme),
      listTileTheme: _listTileTheme,
      segmentedButtonTheme: _segmentedButtonTheme(colorScheme),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final baseScheme = ColorScheme.dark(
      primary: AppColors.primaryDark,
      onPrimary: AppColors.onPrimaryDark,
      primaryContainer: AppColors.primaryContainerDark,
      onPrimaryContainer: AppColors.onPrimaryContainerDark,
      secondary: AppColors.secondaryDark,
      onSecondary: AppColors.onSecondaryDark,
      secondaryContainer: AppColors.secondaryContainerDark,
      onSecondaryContainer: AppColors.onSecondaryContainerDark,
      tertiary: AppColors.tertiaryDark,
      onTertiary: AppColors.onTertiaryDark,
      tertiaryContainer: AppColors.tertiaryContainerDark,
      onTertiaryContainer: AppColors.onTertiaryContainerDark,
      error: AppColors.errorDark,
      onError: AppColors.onErrorDark,
      errorContainer: AppColors.errorContainerDark,
      onErrorContainer: AppColors.onErrorContainerDark,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.onSurfaceDark,
      outline: AppColors.outlineDark,
      outlineVariant: AppColors.outlineVariantDark,
      shadow: Colors.black.withValues(alpha: 0.15),
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    // The flat steps are the true-black canvas; raised steps cap at #121212.
    final colorScheme = baseScheme.copyWith(
      surfaceContainerLowest: AppColors.backgroundDark,
      surfaceContainerLow: AppColors.surfaceDark,
      surfaceContainer: AppColors.surfaceDark,
      surfaceContainerHigh: AppColors.surfaceVariantDark,
      surfaceContainerHighest: AppColors.surfaceVariantDark,
    );
    final textTheme = AppTextStyles.dark(base.textTheme, colorScheme);

    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      colorScheme: colorScheme,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: _appBarTheme(textTheme, colorScheme),
      dividerTheme: _dividerTheme(colorScheme),
      // Sheets are raised surfaces: the #121212 cap above the black canvas.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        modalBackgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: _sheetRadius),
      ),
      inputDecorationTheme: _inputDecorationTheme(
        textTheme,
        colorScheme,
        fillColor: colorScheme.surfaceContainerHigh,
      ),
      snackBarTheme: _snackBarTheme(textTheme, colorScheme),
      cardTheme: _cardTheme(colorScheme),
      chipTheme: _chipTheme(base.chipTheme, colorScheme),
      dialogTheme: _dialogTheme(
        textTheme,
        colorScheme,
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: _buttonTextStyle,
        ),
      ),
      filledButtonTheme: _filledButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      floatingActionButtonTheme: _fabTheme(colorScheme),
      listTileTheme: _listTileTheme,
      segmentedButtonTheme: _segmentedButtonTheme(colorScheme),
    );
  }

  // --- Shared component themes -------------------------------------------

  /// App bar: the canvas itself (no tonal shift), screen title 20/w700.
  static AppBarTheme _appBarTheme(TextTheme textTheme, ColorScheme colors) {
    return AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      toolbarTextStyle: textTheme.bodyMedium,
    );
  }

  /// Hairline dividers: 1px outlineVariant. Structure comes from these, not
  /// card chrome.
  static DividerThemeData _dividerTheme(ColorScheme colors) {
    return DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    );
  }

  /// Cards are real objects again: the dark surface (#15151F) lifts off the
  /// canvas (#0B0B0F) by color, and light cards (#FFFFFF) lift off the cool
  /// off-white canvas with a soft shadow. Premium depth, not hairline rows.
  static CardThemeData _cardTheme(ColorScheme colors) {
    final bool isDark = colors.brightness == Brightness.dark;
    return CardThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 1.5,
      shadowColor: isDark
          ? Colors.transparent
          : Colors.black.withValues(alpha: 0.10),
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: _cardRadius),
    );
  }

  /// Flat 12px text chips: no border, no fill; selected = blue 10% tint.
  static ChipThemeData _chipTheme(ChipThemeData base, ColorScheme colors) {
    final labelStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontFamilyFallback: AppTextStyles.fontFallback,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: colors.onSurface,
    );
    return base.copyWith(
      backgroundColor: colors.surface,
      selectedColor: AppColors.accentElectricBlue.withValues(alpha: 0.10),
      deleteIconColor: colors.onSurfaceVariant,
      labelStyle: labelStyle,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      labelPadding: EdgeInsets.zero,
      secondaryLabelStyle: labelStyle.copyWith(
        color: AppColors.accentElectricBlue,
        fontWeight: FontWeight.w600,
      ),
      secondarySelectedColor: AppColors.accentElectricBlue.withValues(
        alpha: 0.10,
      ),
    );
  }

  static DialogThemeData _dialogTheme(
    TextTheme textTheme,
    ColorScheme colors, {
    Color? backgroundColor,
  }) {
    return DialogThemeData(
      backgroundColor: backgroundColor ?? colors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
      shape: const RoundedRectangleBorder(borderRadius: _cardRadius),
    );
  }

  /// Premium-dark default so even non-migrated or third-party SnackBars match
  /// the app: a layered surface (surfaceContainerHigh — the same step as the
  /// onboarding sheets), onSurface text, the brand primary for actions, and a
  /// tokenized rounded shape. The bespoke [HustlSnack] builds its own surface on
  /// top of a transparent SnackBar; this theme is the floor for everything else.
  static SnackBarThemeData _snackBarTheme(
    TextTheme textTheme,
    ColorScheme colors,
  ) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.surfaceContainerHigh,
      elevation: 2,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1,
      ),
      shape: const RoundedRectangleBorder(borderRadius: _cardRadius),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colors.onSurface,
      ),
      actionTextColor: colors.primary,
      showCloseIcon: true,
      closeIconColor: colors.onSurfaceVariant,
    );
  }

  static InputDecorationTheme _inputDecorationTheme(
    TextTheme textTheme,
    ColorScheme colors, {
    required Color fillColor,
  }) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
      ),
      border: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: colors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: colors.error, width: 1.6),
      ),
    );
  }

  /// The '+' FAB pattern (§12.1): a flat 56px blue circle, white glyph.
  /// Screens attach their own FloatingActionButton; this theme makes every
  /// one consistent.
  static FloatingActionButtonThemeData _fabTheme(ColorScheme colors) {
    return FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 1,
      highlightElevation: 0,
      // Round FABs only. `shape`/`sizeConstraints` here also reach
      // FloatingActionButton.extended, so any extended FAB must set its own
      // `shape: StadiumBorder()` or it gets clipped into a circle.
      shape: const CircleBorder(),
      sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
    );
  }

  static FilledButtonThemeData get _filledButtonTheme {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: _controlRadius),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        textStyle: _buttonTextStyle,
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme colors) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onSurface,
        shape: const RoundedRectangleBorder(borderRadius: _controlRadius),
        side: BorderSide(color: colors.outlineVariant),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        textStyle: _buttonTextStyle,
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme colors) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: _controlRadius),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        textStyle: _buttonTextStyle,
      ),
    );
  }

  static const ListTileThemeData _listTileTheme = ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(
      horizontal: AppSpacing.x2,
      vertical: AppSpacing.x1,
    ),
    minVerticalPadding: AppSpacing.x1,
  );

  /// Quiet segmented control: hairline border, selected = blue 10% tint with
  /// onSurface text (monochrome emphasis, no filled block).
  static SegmentedButtonThemeData _segmentedButtonTheme(ColorScheme colors) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(40)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        textStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontFamilyFallback: AppTextStyles.fontFallback,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        side: WidgetStateProperty.all(
          BorderSide(color: colors.outlineVariant, width: 1),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary.withValues(alpha: 0.10);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.onSurface;
          }
          return colors.onSurfaceVariant;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.hovered)) {
            return colors.primary.withValues(alpha: 0.08);
          }
          return null;
        }),
      ),
    );
  }
}
