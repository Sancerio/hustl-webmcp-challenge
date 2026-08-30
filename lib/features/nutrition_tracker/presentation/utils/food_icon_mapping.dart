/// Maps a food name to one of the 24 full-colour Fluent Emoji (MIT) food glyphs
/// in `assets/icons/food/`. The rules mirror the legacy `emojiForFoodName`
/// keyword list in ORDER, so first-match specificity is preserved (e.g.
/// `sweet potato` resolves before `potato`). Unknown foods fall back to the
/// neutral meal plate — a partial/odd name never renders a wrong colourful guess.
library;

const String _dir = 'assets/icons/food';

class _FoodCatRule {
  const _FoodCatRule(this.category, this.keywords);

  final String category;
  final List<String> keywords;

  bool matches(String text) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}

/// The food glyph asset path for [name] — always non-null (neutral `meal` plate
/// is the guaranteed fallback).
String foodGlyphAsset(String name) {
  final lower = name.toLowerCase();
  for (final rule in _foodCatRules) {
    if (rule.matches(lower)) return '$_dir/food_${rule.category}.svg';
  }
  return '$_dir/food_meal.svg';
}

// Flavoured PRODUCTS win over the produce flavour in the name — 'strawberry
// yogurt' is dairy, not a strawberry. These product keywords don't collide with
// any meat/produce keyword (unlike 'tea'⊂'steak' or 'honey'⊂'honeydew', which
// is why only these are promoted), so they're safe to check first. Everything
// after mirrors the legacy emoji rules in order (specific before generic).
const List<_FoodCatRule> _foodCatRules = [
  // ---- AUDIT TAIL FIXES (round 2) ----
  // Specific products/brands surfaced by the food-glyph audit (tool/) that the
  // generic produce/flavour rules below would otherwise mis-glyph. Each keyword
  // is multi-word or a distinctive brand token, verified collision-free against
  // the rules beneath it via the harness (tool/food_glyph_trace.dart). They sit
  // first so the specific product always beats the produce flavour in the name.

  // Cookies/candy beat nut-butter, dairy 'butter', 'oatmeal' and the produce
  // flavour ('oatmeal raisin cookie' is a cookie; 'peanut butter cup' is candy;
  // 'nutter butter' is a cookie). Must precede the nut-butter rule below.
  _FoodCatRule('sweets', ['cookie', 'peanut butter cup', 'nutter butter']),

  // Branded breakfast cereals -> grains; the box flavour ('strawberry', 'apple
  // jacks') must not win as produce. 'grape nuts'/'fried rice'/'rice cake' also
  // live here so 'grape'/produce/'cake' don't capture them.
  _FoodCatRule('grains', [
    'apple jacks',
    'froot loops',
    'fruit loops',
    'mini wheat',
    'shredded wheat',
    'frosted flake',
    'rice krispie',
    'special k',
    'lucky charms',
    'cocoa puffs',
    'grape nuts',
    'grape-nuts',
    'muesli',
    'wheaties',
    'fried rice',
    'rice cake',
  ]),

  // Cultured/seasonal dairy + common yogurt brands whose Open Food Facts titles
  // often omit the word 'yogurt' ('Yoplait Original Strawberry'). 'eggnog' also
  // here so 'egg'⊂'egg nog' doesn't render a fried egg on a milk drink.
  _FoodCatRule('dairy', [
    'eggnog',
    'egg nog',
    'yoplait',
    'chobani',
    'oikos',
    'fage',
    'siggi',
    'noosa',
    'activia',
    'dannon',
    'danone',
  ]),

  // Snack chips: potato (potato chips) vs flatbread (corn/tortilla chips). The
  // seasoning flavour ('sour cream & onion', 'hint of lime') must not win.
  // ('ruffles' is intentionally omitted: it is a substring of 'truffles'.)
  _FoodCatRule('potato', ['potato chip', 'kettle chip', 'pringles']),
  _FoodCatRule('flatbread', [
    'tortilla chip',
    'corn chip',
    'tostitos',
    'doritos',
  ]),

  // Grape/cherry tomatoes are vegetables, not the fruit they are named after.
  _FoodCatRule('vegetables', ['grape tomato', 'cherry tomato']),

  // Bagels and fruit-bread loaves are bread, not the fruit flavour ('cinnamon
  // raisin bagel', 'raisin bread'). 'english muffin' before the sweets 'muffin'.
  _FoodCatRule('bread', ['bagel', 'raisin bread', 'english muffin']),

  // Sparkling waters (incl. common brands) -> water, not the citrus flavour
  // ('La Croix Lime'). Above the beverage block so 'club soda' reads as water.
  _FoodCatRule('water', [
    'sparkling water',
    'seltzer',
    'la croix',
    'lacroix',
    'club soda',
    'soda water',
    'perrier',
    'topo chico',
  ]),

  // (Anchored tea drinks live in the beverage block below, AFTER the dessert
  // rules, so 'green tea ice cream'/'matcha ice cream' stay sweets while 'peach
  // tea' still beats the produce flavour.)

  // ---- PRODUCT-PROMOTION BLOCK ----
  // Flavoured/composite PRODUCTS win over the produce flavour word in the name
  // ('strawberry ice cream' is a dessert, not a strawberry). These product
  // keywords are checked first; each is verified not to be a substring of an
  // earlier-intended produce food (the harness in tool/food_glyph_trace.dart
  // confirms no regressions). Order within this block is specific-before-generic.

  // Nut/fruit butters are NOT dairy — must beat the generic 'butter' rule and
  // the produce flavour words. ('peanut butter cup', 'apple butter'.)
  _FoodCatRule('nuts', [
    'peanut butter',
    'almond butter',
    'cashew butter',
    'sunflower seed butter',
    'sunflower butter',
    'nut butter',
  ]),
  _FoodCatRule('fruit', ['apple butter']),

  // Fermented/cultured dairy drinks (no produce collision: 'kefir'/'lassi' are
  // not substrings of any produce keyword).
  _FoodCatRule('dairy', ['kefir', 'lassi']),

  // Egg breakfast sandwiches (McMuffin/croissant) are sandwiches, not desserts
  // — caught before the 'muffin' dessert rule so 'mcmuffin'/'egg ... croissant'
  // don't render a cupcake. 'mcmuffin' and 'breakfast sandwich' are anchored.
  _FoodCatRule('sandwich', ['mcmuffin', 'breakfast sandwich']),

  // Pancakes/waffles beat the fruit flavour word, 'buttermilk', AND the dessert
  // 'cake' rule below ('cake'⊂'pancake'), so this MUST precede the cake rule.
  _FoodCatRule('breakfast', ['pancake', 'waffle']),

  // Frozen/baked desserts beat the fruit/produce flavour word ('strawberry ice
  // cream' is a dessert, not a strawberry). 'cheesecake'/'shortcake' precede
  // bare 'cake'; 'pancake' already handled above.
  _FoodCatRule('sweets', ['ice cream', 'gelato', 'sorbet', 'sherbet']),
  _FoodCatRule('sweets', ['cheesecake', 'shortcake', 'cupcake']),
  _FoodCatRule('sweets', ['pudding', 'custard']),
  _FoodCatRule('sweets', ['brownie', 'fudge']),
  _FoodCatRule('sweets', ['pie', 'cobbler', 'tart']),
  _FoodCatRule('sweets', ['cake']),
  _FoodCatRule('sweets', ['muffin']),
  _FoodCatRule('sweets', ['donut', 'doughnut', 'fritter', 'pastry']),
  _FoodCatRule('sweets', ['scone', 'danish']),
  _FoodCatRule('sweets', ['candy', 'licorice', 'macaroon']),
  // 'chocolat' (no trailing e) catches 'pain au chocolat' AND guards against the
  // 'cola'⊂'chocolat' collision by claiming it as sweets before the soda rule.
  _FoodCatRule('sweets', ['chocolate', 'chocolat', 'cocoa']),

  // Cereals / porridge beat the fruit/sweetener flavour word. Brand cereals
  // ('cheerios') and bare 'oats'/'granola'/'bran'/'flakes' included.
  _FoodCatRule('grains', [
    'oatmeal',
    'porridge',
    'oats',
    'cereal',
    'granola',
    'cheerios',
    'raisin bran',
    'bran flakes',
    'oat bran',
    'wheat bran',
    'corn flakes',
    'cornflakes',
  ]),

  // Flavoured cheeses beat the produce flavour word ('strawberry cream
  // cheese', 'cottage cheese with pineapple'). Checked before fruit rules but
  // after sweets so 'cheesecake' stays a dessert.
  _FoodCatRule('cheese', ['cream cheese', 'cottage cheese']),

  // Drinks beat the produce flavour word ('apple juice','peach iced tea',
  // 'orange soda'). None of these tokens are substrings of an earlier produce
  // keyword (guarded: NOT 'tea'⊂steak, NOT bare 'ale'). Anchored multi-words
  // used where a bare token would collide.
  _FoodCatRule('beverage', [
    'juice',
    'lemonade',
    'soda',
    'cola',
    'coke',
    'iced tea',
    'peach tea',
    'green tea',
    'sweet tea',
    'black tea',
    'herbal tea',
    'chai',
    'matcha',
    'oolong',
    'arnold palmer',
    'snapple',
    'kombucha',
    'cider',
    'frappuccino',
    'frappe',
    'macchiato',
    'cappuccino',
    'creamer',
    'energy drink',
    'sports drink',
    'ginger ale',
    'root beer',
    'gatorade',
    'powerade',
    'lassi',
  ]),

  // Loaves/baked breads beat the fruit flavour word ('banana bread',
  // 'cornbread'). 'cornbread' handled here before the 'corn' veg rule.
  _FoodCatRule('bread', ['cornbread', 'banana bread', 'zucchini bread']),

  // ---- SUBSTRING-COLLISION GUARDS ----
  // Each entry claims a word that a later, shorter keyword would wrongly catch
  // as a substring. They must precede the colliding rule. (Verified collisions
  // in tool/food_glyph_trace.dart.)
  _FoodCatRule('nuts', ['macadamia']), //               'mac'⊂macadamia (pasta)
  _FoodCatRule('vegetables', ['butternut', 'squash']), // 'butter'⊂butternut
  _FoodCatRule('vegetables', ['eggplant']), //          'egg'⊂eggplant
  _FoodCatRule('redmeat', ['corned beef']), //          'corn'⊂corned (redmeat!)
  _FoodCatRule('meal', ['popcorn']), //                 'corn'⊂popcorn (snack)
  _FoodCatRule('flatbread', [
    'corn tortilla',
  ]), //      'corn'⊂... before tortilla
  _FoodCatRule('meal', ['goldfish', 'graham']), //  'fish'⊂goldfish,'ham'⊂graham
  _FoodCatRule('vegetables', ['veggie']), //            'egg'⊂veggie
  _FoodCatRule('seafood', [
    'bacon wrapped',
    'wrapped scallop',
  ]), // 'wrap'⊂wrapped
  _FoodCatRule('citrus', ['grapefruit']), //            'grape'⊂grapefruit
  _FoodCatRule('fruit', ['breadfruit']), //             'bread'⊂breadfruit
  _FoodCatRule('flatbread', ['flatbread']), //          'bread'⊂flatbread
  // ---- MISSING-KEYWORD ADDITIONS ----
  // Common foods that previously fell through to the neutral 'meal' plate.
  _FoodCatRule('nuts', ['pistachio']),
  _FoodCatRule('seafood', [
    'tilapia',
    'scallop',
    'clam',
    'mussel',
    'oyster',
    'squid',
    'calamari',
    'anchovy',
    'sardine',
    'halibut',
    'trout',
    'catfish',
    'tilefish',
    'mahi',
    'snapper',
    'haddock',
    'herring',
  ]),
  _FoodCatRule('redmeat', [
    'lamb',
    'pepperoni',
    'salami',
    'prosciutto',
    'pastrami',
    'sausage',
    'hot dog',
    'frankfurter',
    'bratwurst',
    'chorizo',
    'mutton',
    'veal',
    'venison',
    'brisket',
  ]),
  _FoodCatRule('poultry', ['wing', 'drumstick', 'nugget']),
  _FoodCatRule('pasta', [
    'lasagna',
    'lasagne',
    'ravioli',
    'gnocchi',
    'fettuccine',
    'penne',
    'linguine',
    'macaroni',
  ]),
  _FoodCatRule('flatbread', ['naan', 'pita', 'roti', 'chapati']),
  _FoodCatRule('sweets', ['syrup', 'maple']), //        sweetener -> sweets
  // ---- CONDIMENT / SAUCE GUARDS ----
  // Sauces and dressings have no glyph of their own; the honest plate is the
  // neutral 'meal'. These keywords beat the produce flavour words ('tomato
  // ketchup' is not a tomato, 'caesar salad dressing' is not greens). None
  // collide with a produce/protein keyword as a substring.
  _FoodCatRule('meal', [
    'ketchup',
    'salsa',
    'aioli',
    'mayo',
    'mayonnaise',
    'gravy',
    'pesto',
    'dressing',
    'mustard',
    'vinaigrette',
    'marinara',
    'sriracha',
    'relish',
    'chutney',
    'hummus',
  ]),

  // Cereal/pastry 'toast' collisions: claim them before the bread 'toast' rule.
  _FoodCatRule('grains', ['toast crunch']), //          cereal, not toast
  _FoodCatRule('sweets', ['toaster strudel', 'toaster pastry']), // pastry
  // ---- PROTEIN-PROMOTION BLOCK ----
  // The headline protein beats the sauce/glaze flavour word ('orange chicken'
  // is poultry, not citrus; 'lemon herb salmon' is seafood). Mirrors the
  // dessert promotion. Seafood precedes redmeat so 'tuna steak' (a fish cut)
  // stays seafood. Cheesesteak/cheeseburger stay sandwich (claimed first).
  _FoodCatRule('sandwich', ['cheesesteak', 'cheeseburger', 'philly']),
  _FoodCatRule('poultry', [
    'turkey bacon',
    'chicken bacon',
  ]), // poultry, not bacon
  _FoodCatRule('seafood', [
    'salmon',
    'tuna',
    'shrimp',
    'prawn',
    'cod',
    'crab',
    'lobster',
  ]),
  _FoodCatRule('poultry', ['chicken', 'poultry', 'turkey']),
  _FoodCatRule('redmeat', ['beef', 'steak', 'pork']),

  // ---- LEGACY ORDERED RULES (specific before generic) ----
  _FoodCatRule('dairy', ['yogurt', 'yoghurt', 'milk']),
  _FoodCatRule('dairy', ['butter']),
  _FoodCatRule('beverage', ['smoothie', 'milkshake', 'shake']),
  // Per-fruit glyphs (Fluent Emoji Flat). Each routes to its own recognizable
  // SVG instead of the generic apple-style `food_fruit.svg`. The substring
  // collision guards above still fire FIRST (e.g. 'banana bread'->bread,
  // 'apple jacks'->grains, 'apple butter'->fruit, 'grapefruit'->citrus,
  // 'grape/cherry tomato'->vegetables, 'bitter melon'->vegetables), so the
  // produce flavour only wins when nothing more specific claimed it.
  // 'pineapple' MUST precede 'apple' ('apple'⊂'pineapple') so it keeps its own
  // glyph instead of rendering the red apple.
  _FoodCatRule('pineapple', ['pineapple']),
  _FoodCatRule('apple', ['apple', 'fuji', 'gala', 'granny smith']),
  // 'banana bread' is already claimed as bread above; bare banana -> banana.
  _FoodCatRule('banana', ['banana', 'plantain']),
  _FoodCatRule('grapes', ['grape', 'raisin']),
  _FoodCatRule('strawberry', ['strawberry', 'strawberries']),
  // Berry stems: include the plural ('blueberries'/'cherries'/'berries' do not
  // contain the singular keyword, so both forms are listed explicitly).
  _FoodCatRule('blueberries', [
    'blueberry',
    'blueberries',
    'blackberry',
    'blackberries',
    'raspberry',
    'raspberries',
    'berry',
    'berries',
  ]),
  _FoodCatRule('cherry', ['cherry', 'cherries']),
  _FoodCatRule('peach', ['peach', 'nectarine']),
  _FoodCatRule('mango', ['mango']),
  // citrus produce: grapefruit must beat the 'grape' fruit rule above, so
  // 'grapefruit' is listed here explicitly (checked after bare 'grape' but the
  // 'grape' rule already fired — so grapefruit is promoted ABOVE 'grape').
  _FoodCatRule('tangerine', ['orange', 'mandarin', 'tangerine']),
  _FoodCatRule('citrus', ['citrus']),
  _FoodCatRule('lemon', ['lemon']),
  _FoodCatRule('citrus', ['lime']),
  _FoodCatRule('vegetables', ['bitter melon']), //      gourd, not sweet melon
  _FoodCatRule('watermelon', ['watermelon']),
  _FoodCatRule('fruit', ['melon', 'cantaloupe', 'honeydew']),
  _FoodCatRule('kiwi', ['kiwi']),
  _FoodCatRule('avocado', ['avocado', 'guacamole']),
  _FoodCatRule('vegetables', ['tomato']),
  _FoodCatRule('leafy', ['lettuce', 'kale', 'spinach', 'greens']),
  _FoodCatRule('leafy', ['salad']),
  _FoodCatRule('vegetables', ['broccoli', 'cauliflower']),
  _FoodCatRule('vegetables', ['cucumber', 'pickle']),
  _FoodCatRule('vegetables', ['carrot']),
  _FoodCatRule('vegetables', ['garlic']),
  _FoodCatRule('vegetables', ['onion']),
  _FoodCatRule('vegetables', ['corn', 'maize']),
  // Common vegetables that previously fell to the neutral 'meal' plate. 'pepper'
  // is safe here: pepperoni/jalapeno-on-pizza etc. with their own categories are
  // already claimed earlier (redmeat 'pepperoni', protein/pizza promotion).
  // NOTE: bare 'pea' is NOT used — it is a substring of 'pear' (fruit) and
  // 'peanut' (nuts). Anchored pea forms are listed instead.
  _FoodCatRule('vegetables', [
    'pepper',
    'zucchini',
    'courgette',
    'asparagus',
    'celery',
    'radish',
    'beet',
    'peas',
    'snap pea',
    'snow pea',
    'split pea',
    'chickpea',
    'green bean',
    'brussels',
    'cabbage',
    'mushroom',
    'squash',
    'eggplant',
    'aubergine',
    'okra',
    'leek',
  ]),
  // Pear gets its own Fluent glyph; the rest share the generic fruit plate.
  _FoodCatRule('pear', ['pear']),
  // Common fruits with no prior keyword (fell to 'meal').
  _FoodCatRule('fruit', [
    'passion fruit',
    'dragon fruit',
    'star fruit',
    'papaya',
    'pomegranate',
    'apricot',
    'plum',
    'fig',
    'guava',
    'lychee',
    'persimmon',
    'date',
    'coconut',
  ]),
  _FoodCatRule('potato', ['potato', 'fries', 'hash brown']),
  _FoodCatRule('potato', ['sweet potato', 'yam']),
  _FoodCatRule('grains', ['rice', 'risotto']),
  _FoodCatRule('bread', ['bread', 'toast', 'bagel']),
  _FoodCatRule('bread', ['bagel']),
  _FoodCatRule('bread', ['pretzel']),
  _FoodCatRule('breakfast', ['waffle']),
  _FoodCatRule('breakfast', ['pancake']),
  _FoodCatRule('grains', ['oatmeal', 'porridge', 'cereal']),
  _FoodCatRule('pasta', ['noodle', 'ramen', 'pho']),
  _FoodCatRule('pasta', [
    'dumpling',
    'gyoza',
    'wonton',
    'potsticker',
    'pierogi',
  ]),
  _FoodCatRule('pasta', ['pasta', 'spaghetti', 'mac']),
  _FoodCatRule('bread', ['baguette']),
  _FoodCatRule('flatbread', ['tortilla', 'flatbread']),
  _FoodCatRule('pizza', ['pizza']),
  _FoodCatRule('sandwich', ['sandwich', 'sub']),
  _FoodCatRule('sandwich', ['burrito', 'wrap']),
  _FoodCatRule('sandwich', ['taco']),
  _FoodCatRule('sandwich', ['burger']),
  _FoodCatRule('potato', ['fries']),
  _FoodCatRule('eggs', ['egg']),
  _FoodCatRule('cheese', ['cheese']),
  _FoodCatRule('redmeat', ['bacon']),
  _FoodCatRule('poultry', ['chicken', 'poultry', 'turkey']),
  _FoodCatRule('redmeat', ['beef', 'steak']),
  _FoodCatRule('redmeat', ['pork', 'ham']),
  _FoodCatRule('seafood', ['fish', 'salmon', 'tuna', 'cod']),
  _FoodCatRule('seafood', ['shrimp', 'prawn']),
  _FoodCatRule('seafood', ['crab', 'lobster']),
  _FoodCatRule('dairy', ['butter']),
  _FoodCatRule('nuts', ['peanut', 'nuts', 'almond', 'cashew']),
  _FoodCatRule('nuts', ['walnut', 'hazelnut']),
  _FoodCatRule('sweets', ['honey']),
  _FoodCatRule('sweets', ['chocolate', 'cocoa']),
  _FoodCatRule('sweets', ['cookie', 'biscuit']),
  _FoodCatRule('sweets', ['cupcake', 'muffin']),
  _FoodCatRule('sweets', ['cake']),
  _FoodCatRule('sweets', ['ice cream', 'gelato']),
  _FoodCatRule('sweets', ['donut']),
  _FoodCatRule('beverage', ['coffee', 'latte', 'espresso']),
  // 'steamed <thing>' with no earlier match falls to the neutral plate, NOT to
  // the bare 'tea' rule below ('tea' is a substring of 'steamed').
  _FoodCatRule('meal', ['steamed']),
  _FoodCatRule('beverage', ['tea']),
  _FoodCatRule('beverage', ['soda', 'cola', 'smoothie', 'shake']),
  _FoodCatRule('beverage', ['juice']),
  _FoodCatRule('water', ['water']),
];
