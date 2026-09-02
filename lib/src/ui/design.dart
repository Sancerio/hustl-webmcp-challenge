import 'package:flutter/material.dart';

const ink = Color(0xFF0B1220);
const muted = Color(0xFF61708A);
const canvas = Color(0xFFF4F7FB);
const blue = Color(0xFF2864DC);
const line = Color(0xFFDCE3EE);

ThemeData evaluatorTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    brightness: Brightness.light,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: canvas,
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      color: ink,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(color: ink, height: 1.45),
    bodyMedium: TextStyle(color: muted, height: 1.45),
  ),
  cardTheme: const CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      side: BorderSide(color: line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
);

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding ?? const EdgeInsets.all(20), child: child),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 24),
    ],
  );
}
