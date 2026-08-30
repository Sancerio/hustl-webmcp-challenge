import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/utils/food_icon_mapping.dart';

void main() {
  String cat(String name) => foodGlyphAsset(
    name,
  ).replaceFirst('assets/icons/food/food_', '').replaceFirst('.svg', '');

  group('foodGlyphAsset', () {
    test('common fruits resolve to their own specific glyph', () {
      // The user flagged these: a banana should look like a banana, not the
      // generic apple-style fruit plate. Each routes to its own Fluent glyph.
      expect(cat('Banana'), 'banana');
      expect(cat('Grapes'), 'grapes');
      expect(cat('Blueberries'), 'blueberries');
      expect(cat('Strawberry'), 'strawberry');
      expect(cat('Cherry'), 'cherry');
      expect(cat('Watermelon'), 'watermelon');
      expect(cat('Peach'), 'peach');
      expect(cat('Pineapple'), 'pineapple');
      expect(cat('Mango'), 'mango');
      expect(cat('Apple'), 'apple');
      expect(cat('Pear'), 'pear');
      expect(cat('Kiwi'), 'kiwi');
      expect(cat('Lemon'), 'lemon');
      expect(cat('Tangerine'), 'tangerine');
      expect(cat('Orange'), 'tangerine');
      // Plural/compound forms still hit the berry/cherry glyphs.
      expect(cat('Mixed berries'), 'blueberries');
      expect(cat('Cherries'), 'cherry');
      expect(cat('Raspberry'), 'blueberries');
      expect(cat('Nectarine'), 'peach');
      // Unlisted fruits still fall back to the generic fruit plate.
      expect(cat('Papaya'), 'fruit');
      expect(cat('Cantaloupe'), 'fruit');
    });

    test('per-fruit glyphs do not break the substring-collision guards', () {
      // The fruit flavour must NOT win when a more specific rule claimed it.
      expect(cat('Banana bread'), 'bread');
      expect(cat('Apple Jacks'), 'grains');
      expect(cat('Apple butter'), 'fruit');
      expect(cat('Apple juice'), 'beverage');
      expect(cat('Pink grapefruit'), 'citrus');
      expect(cat('Grape tomatoes'), 'vegetables');
      expect(cat('Cherry tomatoes'), 'vegetables');
      expect(cat('Cinnamon Raisin Bagel'), 'bread');
      expect(cat('Strawberry ice cream'), 'sweets');
      expect(cat('Orange chicken'), 'poultry');
      expect(cat('Bitter melon'), 'vegetables');
      expect(cat('Banana pancakes'), 'breakfast');
      // 'apple'⊂'pineapple' — pineapple keeps its own glyph, not the red apple.
      expect(cat('Pineapple'), 'pineapple');
    });

    test('maps representative foods to the right category glyph', () {
      expect(cat('Banana'), 'banana');
      expect(cat('Grilled chicken breast'), 'poultry');
      expect(cat('Ribeye steak'), 'redmeat');
      expect(cat('Salmon fillet'), 'seafood');
      expect(cat('Greek yogurt'), 'dairy');
      expect(cat('Spaghetti bolognese'), 'pasta');
      expect(cat('Sourdough bread'), 'bread');
      expect(cat('Cupcake'), 'sweets');
      expect(cat('Sparkling water'), 'water');
    });

    test('order-sensitive: the specific keyword wins', () {
      // 'avocado' resolves before 'toast' (bread); 'mac' before 'cheese'.
      expect(cat('Avocado toast'), 'avocado');
      expect(cat('Mac and cheese'), 'pasta');
      expect(cat('Sweet potato fries'), 'potato');
    });

    test('flavoured dairy/beverage products beat the produce in the name', () {
      // A flavoured yogurt is dairy, not the berry it's flavoured with.
      expect(cat('Greek strawberry yogurt'), 'dairy');
      expect(cat('Blueberry yoghurt'), 'dairy');
      expect(cat('Whole milk'), 'dairy');
      expect(cat('Mango smoothie'), 'beverage');
      expect(cat('Banana protein shake'), 'beverage');
      // Regression guard: the dairy/beverage promotion must not swallow the
      // real produce/meat keywords it deliberately avoided colliding with.
      expect(cat('Ribeye steak'), 'redmeat');
      expect(cat('Honeydew melon'), 'fruit');
      expect(cat('Iced tea'), 'beverage');
      expect(cat('Strawberry'), 'strawberry');
    });

    test('audit tail fixes: branded/compound products resolve correctly', () {
      // Branded breakfast cereals -> grains (the box flavour must not win).
      expect(cat('Apple Jacks'), 'grains');
      expect(cat('Strawberry Frosted Mini Wheats'), 'grains');
      expect(cat('Quaker Rice Cakes Caramel Corn'), 'grains');
      expect(cat('Pineapple fried rice'), 'grains');
      // Yogurt brands that omit "yogurt" + seasonal dairy.
      expect(cat('Yoplait Original Strawberry'), 'dairy');
      expect(cat('Egg nog'), 'dairy');
      // Snack chips split potato vs corn/tortilla.
      expect(cat('Pringles Sour Cream & Onion'), 'potato');
      expect(cat('Tostitos Hint of Lime Tortilla Chips'), 'flatbread');
      // Grape/cherry tomatoes are vegetables, not the fruit they're named for.
      expect(cat('Grape tomatoes'), 'vegetables');
      expect(cat('Cherry tomatoes'), 'vegetables');
      // Bagels/fruit loaves are bread; english muffin beats the sweets 'muffin'.
      expect(cat('Cinnamon Raisin Bagel'), 'bread');
      expect(cat('English muffin'), 'bread');
      // Sparkling waters -> water, not the citrus flavour.
      expect(cat('La Croix Lime'), 'water');
      // Cookies/candy beat nut-butter, oatmeal and dairy 'butter'.
      expect(cat('Oatmeal Raisin Cookie'), 'sweets');
      expect(cat('Reese\'s Peanut Butter Cups'), 'sweets');
      expect(cat('Nutter Butter'), 'sweets');
    });

    test('tea drinks beat produce but stay below desserts', () {
      expect(cat('Snapple Peach Tea'), 'beverage');
      expect(cat('Matcha latte'), 'beverage');
      // ...but a tea-flavoured dessert is still a dessert.
      expect(cat('Green tea ice cream'), 'sweets');
    });

    test('substring-collision guards hold', () {
      // 'butter' (dairy) must not swallow nut butters.
      expect(cat('Peanut butter'), 'nuts');
      expect(cat('Almond butter'), 'nuts');
      // 'ruffles'⊂'truffles' was deliberately omitted from the chip rule.
      expect(cat('Chocolate truffles'), 'sweets');
      // 'tea'⊂'steamed' must not turn steamed dishes into a drink.
      expect(cat('Steamed dumplings'), 'pasta');
      expect(cat('Steamed broccoli'), 'vegetables');
      // Long-cut fish stays seafood even with 'steak' in the name.
      expect(cat('Tuna steak'), 'seafood');
      // 'grape'⊂'grapefruit'.
      expect(cat('Pink grapefruit'), 'citrus');
    });

    test('every rule points at a real downloaded asset name', () {
      // Guards against a typo'd category that would 404 at runtime.
      const known = {
        'fruit',
        'banana',
        'grapes',
        'blueberries',
        'strawberry',
        'cherry',
        'watermelon',
        'peach',
        'pineapple',
        'mango',
        'apple',
        'pear',
        'kiwi',
        'lemon',
        'tangerine',
        'citrus',
        'vegetables',
        'leafy',
        'avocado',
        'potato',
        'grains',
        'bread',
        'flatbread',
        'breakfast',
        'pasta',
        'pizza',
        'sandwich',
        'eggs',
        'cheese',
        'dairy',
        'poultry',
        'redmeat',
        'seafood',
        'nuts',
        'sweets',
        'beverage',
        'water',
        'meal',
      };
      for (final name in [
        'apple',
        'banana',
        'grapes',
        'blueberries',
        'strawberry',
        'cherry',
        'watermelon',
        'peach',
        'pineapple',
        'mango',
        'pear',
        'kiwi',
        'lemon',
        'tangerine',
        'pizza',
        'tea',
        'qwerty-unknown',
      ]) {
        expect(
          known.contains(cat(name)),
          isTrue,
          reason: 'bad category for $name',
        );
      }
    });

    test('unknown food falls back to the neutral meal plate', () {
      expect(cat('Mystery stew'), 'meal');
      expect(cat(''), 'meal');
    });
  });
}
