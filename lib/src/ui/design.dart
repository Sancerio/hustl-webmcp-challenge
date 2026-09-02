import 'package:flutter/material.dart';

const hustleCanvas = Color(0xFF09090D);
const hustleSurface = Color(0xFF15151F);
const hustleSurfaceHigh = Color(0xFF1F2230);
const hustleBorder = Color(0xFF292C39);
const hustleText = Color(0xFFF7F7FA);
const hustleMuted = Color(0xFFA7A8B3);
const hustleBlue = Color(0xFF3B82F6);
const hustleEmerald = Color(0xFF10B981);
const hustleAmber = Color(0xFFF59E0B);
const hustleLavender = Color(0xFF8B5CF6);
const macroProtein = Color(0xFF34D399);
const macroCarbs = Color(0xFF3B82F6);
const macroFat = Color(0xFFF59E0B);

// Compatibility aliases keep proposal widgets focused on disclosure logic
// while the evaluator adopts Hustl's production palette.
const canvas = hustleCanvas;
const surface = hustleSurface;
const ink = hustleText;
const muted = hustleMuted;
const blue = hustleBlue;
const line = hustleBorder;

ThemeData evaluatorTheme() {
  const scheme = ColorScheme.dark(
    primary: hustleBlue,
    onPrimary: Colors.white,
    secondary: hustleLavender,
    tertiary: hustleEmerald,
    error: Color(0xFFF87171),
    surface: hustleSurface,
    onSurface: hustleText,
    onSurfaceVariant: hustleMuted,
    outline: hustleBorder,
    outlineVariant: hustleBorder,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: hustleCanvas,
    canvasColor: hustleCanvas,
    dividerColor: hustleBorder,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        color: hustleText,
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        color: hustleText,
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: hustleText,
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: hustleText, fontSize: 15, height: 1.4),
      bodyMedium: TextStyle(color: hustleMuted, fontSize: 14, height: 1.4),
      bodySmall: TextStyle(color: hustleMuted, fontSize: 12, height: 1.35),
      labelLarge: TextStyle(
        color: hustleText,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: hustleSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: hustleBorder),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: hustleSurface,
      foregroundColor: hustleText,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: hustleText,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: hustleSurface,
      indicatorColor: Color(0xFF20345F),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(color: hustleText, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: hustleMuted)),
      height: 72,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: hustleBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: hustleText,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        side: const BorderSide(color: hustleBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: hustleBlue),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: hustleBlue,
      linearTrackColor: hustleSurfaceHigh,
    ),
  );
}

class HustlPanel extends StatelessWidget {
  const HustlPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.color = hustleSurface,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor ?? hustleBorder),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) =>
      HustlPanel(padding: padding ?? const EdgeInsets.all(16), child: child);
}

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class HustlSectionTitle extends StatelessWidget {
  const HustlSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class HustlAvatar extends StatelessWidget {
  const HustlAvatar({super.key});

  @override
  Widget build(BuildContext context) => const CircleAvatar(
    radius: 18,
    backgroundColor: Color(0xFF17223C),
    child: Text(
      'A',
      style: TextStyle(color: hustleText, fontWeight: FontWeight.w700),
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: SizedBox.square(dimension: size),
  );
}
