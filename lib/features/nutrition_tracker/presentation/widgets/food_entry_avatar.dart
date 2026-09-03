import 'package:flutter/material.dart';

import 'food_glyph.dart';

class FoodEntryAvatar extends StatelessWidget {
  const FoodEntryAvatar({
    super.key,
    required this.name,
    this.source,
    this.radius = 18,
  });

  final String name;
  final String? source;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = source == null ? null : foodSourceIcon(source!);
    final iconTooltip = source == null ? null : foodSourceLabel(source!);

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: FoodGlyph(name: name, size: radius * 1.35),
    );

    if (icon == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Tooltip(
            message: iconTooltip ?? '',
            child: Container(
              width: radius * 0.95,
              height: radius * 0.95,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(
                icon,
                size: radius * 0.55,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String emojiForFoodName(String name) {
  final lower = name.toLowerCase();
  for (final rule in _emojiRules) {
    if (rule.matches(lower)) return rule.emoji;
  }
  return '🍽️';
}

IconData? foodSourceIcon(String source) {
  final normalized = source.trim().toLowerCase();
  if (normalized == 'meal_scan' || normalized == 'meal_scan_item') {
    return Icons.auto_awesome;
  }
  if (normalized == 'label_scan') return Icons.document_scanner_outlined;
  if (normalized == 'barcode') return Icons.qr_code;
  if (normalized == 'quick_add') return Icons.edit_outlined;
  if (normalized == 'recipe') return Icons.menu_book_outlined;
  if (normalized == 'copy') return Icons.copy_all_outlined;
  return null;
}

String? foodSourceLabel(String source) {
  final normalized = source.trim().toLowerCase();
  if (normalized == 'meal_scan' || normalized == 'meal_scan_item') {
    return 'Photo estimate';
  }
  if (normalized == 'label_scan') return 'Label scan';
  if (normalized == 'barcode') return 'Barcode';
  if (normalized == 'quick_add') return 'Quick add';
  if (normalized == 'recipe') return 'Recipe';
  if (normalized == 'copy') return 'Copied';
  return null;
}

class _EmojiRule {
  const _EmojiRule(this.emoji, this.keywords);

  final String emoji;
  final List<String> keywords;

  bool matches(String text) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}

const List<_EmojiRule> _emojiRules = [
  _EmojiRule('🍎', ['apple', 'fuji', 'gala', 'granny smith']),
  _EmojiRule('🍌', ['banana', 'plantain']),
  _EmojiRule('🍇', ['grape', 'raisin']),
  _EmojiRule('🍓', ['strawberry']),
  _EmojiRule('🫐', ['blueberry', 'blackberry', 'raspberry', 'berry']),
  _EmojiRule('🍒', ['cherry']),
  _EmojiRule('🍑', ['peach', 'nectarine']),
  _EmojiRule('🥭', ['mango']),
  _EmojiRule('🍍', ['pineapple']),
  _EmojiRule('🍊', ['orange', 'citrus', 'mandarin', 'tangerine']),
  _EmojiRule('🍋', ['lemon', 'lime']),
  _EmojiRule('🍈', ['melon', 'cantaloupe', 'honeydew']),
  _EmojiRule('🥝', ['kiwi']),
  _EmojiRule('🥑', ['avocado', 'guacamole']),
  _EmojiRule('🍅', ['tomato']),
  _EmojiRule('🥬', ['lettuce', 'kale', 'spinach', 'greens']),
  _EmojiRule('🥗', ['salad']),
  _EmojiRule('🥦', ['broccoli', 'cauliflower']),
  _EmojiRule('🥒', ['cucumber', 'pickle']),
  _EmojiRule('🥕', ['carrot']),
  _EmojiRule('🧄', ['garlic']),
  _EmojiRule('🧅', ['onion']),
  _EmojiRule('🌽', ['corn', 'maize']),
  _EmojiRule('🥔', ['potato', 'fries', 'hash brown']),
  _EmojiRule('🍠', ['sweet potato', 'yam']),
  _EmojiRule('🍚', ['rice', 'risotto']),
  _EmojiRule('🍞', ['bread', 'toast', 'bagel']),
  _EmojiRule('🥯', ['bagel']),
  _EmojiRule('🥨', ['pretzel']),
  _EmojiRule('🧇', ['waffle']),
  _EmojiRule('🥞', ['pancake']),
  _EmojiRule('🥣', ['oatmeal', 'porridge', 'cereal']),
  _EmojiRule('🍜', ['noodle', 'ramen', 'pho']),
  _EmojiRule('🍝', ['pasta', 'spaghetti', 'mac']),
  _EmojiRule('🥖', ['baguette']),
  _EmojiRule('🫓', ['tortilla', 'flatbread']),
  _EmojiRule('🍕', ['pizza']),
  _EmojiRule('🥪', ['sandwich', 'sub']),
  _EmojiRule('🌯', ['burrito', 'wrap']),
  _EmojiRule('🌮', ['taco']),
  _EmojiRule('🍔', ['burger']),
  _EmojiRule('🍟', ['fries']),
  _EmojiRule('🥚', ['egg']),
  _EmojiRule('🧀', ['cheese']),
  _EmojiRule('🥛', ['milk', 'yogurt']),
  _EmojiRule('🥓', ['bacon']),
  _EmojiRule('🍗', ['chicken', 'poultry', 'turkey']),
  _EmojiRule('🥩', ['beef', 'steak']),
  _EmojiRule('🍖', ['pork', 'ham']),
  _EmojiRule('🐟', ['fish', 'salmon', 'tuna', 'cod']),
  _EmojiRule('🦐', ['shrimp', 'prawn']),
  _EmojiRule('🦀', ['crab', 'lobster']),
  _EmojiRule('🧈', ['butter']),
  _EmojiRule('🥜', ['peanut', 'nuts', 'almond', 'cashew']),
  _EmojiRule('🌰', ['walnut', 'hazelnut']),
  _EmojiRule('🍯', ['honey']),
  _EmojiRule('🍫', ['chocolate', 'cocoa']),
  _EmojiRule('🍪', ['cookie', 'biscuit']),
  _EmojiRule('🧁', ['cupcake', 'muffin']),
  _EmojiRule('🍰', ['cake']),
  _EmojiRule('🍦', ['ice cream', 'gelato']),
  _EmojiRule('🍩', ['donut']),
  _EmojiRule('☕', ['coffee', 'latte', 'espresso']),
  _EmojiRule('🍵', ['tea']),
  _EmojiRule('🥤', ['soda', 'cola', 'smoothie', 'shake']),
  _EmojiRule('🧃', ['juice']),
  _EmojiRule('💧', ['water']),
];
