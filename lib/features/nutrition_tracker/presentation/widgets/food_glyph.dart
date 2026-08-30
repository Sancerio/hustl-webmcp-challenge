import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/food_icon_mapping.dart';

/// A full-colour Fluent Emoji (MIT) food glyph for [name], resolved via
/// [foodGlyphAsset].
///
/// Rendered WITHOUT a colour filter — unlike [HustlIcon], which tints SVGs to a
/// single hue — so the flat illustration keeps its own colours. The Flat Fluent
/// SVGs are solid-fill only (no gradients/filters), so flutter_svg renders them
/// cleanly. Decorative: the food name is shown alongside, so the glyph carries
/// no semantics label.
class FoodGlyph extends StatelessWidget {
  const FoodGlyph({super.key, required this.name, this.size = 24});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(foodGlyphAsset(name), width: size, height: size);
  }
}
