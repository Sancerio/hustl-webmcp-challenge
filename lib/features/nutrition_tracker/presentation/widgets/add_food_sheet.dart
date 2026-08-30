import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

import '../../domain/models/food.dart';
import '../../domain/models/food_log_entry.dart';
import '../utils/go_to_ranking.dart';
import '../../domain/repositories/food_log_repository.dart';
import '../../domain/repositories/food_repository.dart';
import '../bloc/food_search_bloc.dart';
import '../bloc/food_search_event.dart';
import 'add_food_method_ribbon.dart';
import 'add_food_scan_menu.dart';
import 'add_food_search_view.dart';
import 'barcode_scan_dialog.dart';
import 'copy_from_day_sheet.dart';
import 'food_plate.dart';
import 'meal_photo_scan_dialog.dart';
import 'nutrition_label_scan_dialog.dart';
import 'plate_review_sheet.dart';
import 'recipes_browser.dart';
import 'quick_add_dialog.dart';

/// Search-first add-food sheet: a search field (with a scan shortcut) over the
/// Suggested-for-now / Recent / Favorites landing, plus a quiet row of secondary
/// actions (quick add, recipes, copy a day).
///
/// When [enablePlate] is true (the default) picks STAGE into a plate (a staging
/// tray held in state) and a single "Log foods (N)" bar commits the whole plate
/// at once — the bar is invisible until at least one food is staged. When
/// [enablePlate] is false the sheet logs each pick immediately and stays open,
/// which preserves the `/add-food` quick action's fire-and-return contract.
class AddFoodSheet extends StatefulWidget {
  const AddFoodSheet({
    super.key,
    required this.date,
    required this.onAdd,
    this.initialQuery,
    this.initialLoggedAt,
    this.enablePlate = true,
    this.dayTargetCalories,
    this.dayConsumedCalories,
  });

  final DateTime date;
  final ValueChanged<List<FoodLogEntry>> onAdd;
  final String? initialQuery;
  final DateTime? initialLoggedAt;

  /// Whether picks stage into a plate (true) or log immediately (false).
  final bool enablePlate;

  /// The day's calorie target and calories already logged, forwarded to the
  /// meal-scan result so it can show a live target-vs-consumed comparison.
  /// Null where the diary totals aren't in scope (the comparison is omitted).
  final double? dayTargetCalories;
  final double? dayConsumedCalories;

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  final _controller = TextEditingController();
  final _searchFocus = FocusNode();
  bool _seededInitialQuery = false;
  List<FoodLogEntry> _recentEntries = [];
  // "Suggested for now": the foods you usually log around this time of day,
  // ranked tz-aware on the backend and loaded with Recent in one /suggestions
  // call (no client-side 7-day fan-out).
  List<FoodLogEntry> _suggested = const [];
  List<Food> _favoriteFoods = [];
  final Set<String> _favoriteIds = {};
  // The staging tray (plate mode only). Empty until the first pick is staged;
  // a non-empty plate reveals the sticky "Log foods (N)" bar.
  final List<FoodLogEntry> _plate = [];
  late final DateTime _loggedAtSeed;

  // Speed (false, default) vs context (true). In context mode each stage auto-
  // opens the plate review so you can tweak as you go; in speed mode a stage
  // stays in search for the next quick add. Restored from prefs on init.
  bool _contextMode = false;

  // --- lifecycle ---

  @override
  void initState() {
    super.initState();
    _loadContextMode();
    final seed = widget.initialLoggedAt?.toLocal() ?? DateTime.now();
    _loggedAtSeed = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      seed.hour,
      seed.minute,
      seed.second,
    );
    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
    }
    _loadSuggestions();
    _loadFavorites();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  DateTime _defaultLoggedAt() => _loggedAtSeed;

  void _closeSheet(BuildContext context) {
    if (context.canPop()) context.pop();
  }

  // --- data loading ---

  /// Loads the add-food empty state (Suggested for now + Recent) in a single
  /// backend round-trip, replacing the old 7×getLogsForDate fan-out. The backend
  /// computes recents (distinct-by-recency over a 30-day window) and the tz-aware
  /// time-of-day suggestions, so the client just renders the two arrays.
  Future<void> _loadSuggestions() async {
    final repo = GetIt.instance<FoodLogRepository>();
    final result = await repo.getSuggestions(
      tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );
    if (!mounted) return;
    setState(() {
      _recentEntries = result.recents;
      _suggested = result.suggestions;
    });
  }

  Future<void> _loadFavorites() async {
    final repo = GetIt.instance<FoodRepository>();
    try {
      final idsFuture = repo
          .listFavoriteIds(limit: 500)
          .catchError((_) => <String>{});
      final foodsFuture = repo
          .listFavorites(limit: 10)
          .catchError((_) => <Food>[]);
      final results = await Future.wait<Object>([idsFuture, foodsFuture]);
      final ids = results[0] as Set<String>;
      final foods = results[1] as List<Food>;
      final resolvedIds = ids.isNotEmpty
          ? ids
          : foods.map((food) => food.id).toSet();
      if (!mounted) return;
      setState(() {
        _favoriteFoods = foods;
        _favoriteIds
          ..clear()
          ..addAll(resolvedIds);
      });
    } catch (_) {
      // Favorites are best-effort; leave the existing list in place.
    }
  }

  Future<void> _loadContextMode() async {
    if (!widget.enablePlate) return;
    final prefs = GetIt.instance<PreferencesService>();
    final mode = await prefs.getAddFoodContextMode();
    if (!mounted) return;
    setState(() => _contextMode = mode);
  }

  Future<void> _toggleContextMode() async {
    final next = !_contextMode;
    setState(() => _contextMode = next);
    await GetIt.instance<PreferencesService>().setAddFoodContextMode(next);
  }

  List<FoodLogEntry> _latestEntries() {
    // Recents already exclude any food shown under "Suggested for now"
    // (de-duped server-side), but keep the goToFoodKey exclusion as a
    // belt-and-suspenders guard so the two sections never repeat.
    final suggestedKeys = _suggested.map(goToFoodKey).toSet();
    return _recentEntries
        .where((e) => !suggestedKeys.contains(goToFoodKey(e)))
        .take(8)
        .toList(growable: false);
  }

  bool _isFavoriteFood(Food food) => _favoriteIds.contains(food.id);

  // --- entry construction ---

  FoodLogEntry _entryFromFood(
    Food food,
    double grams, {
    String? id,
    DateTime? loggedAt,
    String? source,
  }) {
    final factor = grams / 100;
    return FoodLogEntry(
      id: id ?? 'temp-${DateTime.now().microsecondsSinceEpoch}',
      date: widget.date,
      loggedAt: loggedAt ?? _defaultLoggedAt(),
      servingGrams: grams,
      calories: (food.caloriesPer100g ?? 0) * factor,
      proteinGrams: (food.proteinPer100g ?? 0) * factor,
      carbsGrams: (food.carbsPer100g ?? 0) * factor,
      fatGrams: (food.fatPer100g ?? 0) * factor,
      fiberGrams: food.fiberPer100g == null
          ? null
          : food.fiberPer100g! * factor,
      sugarGrams: food.sugarPer100g == null
          ? null
          : food.sugarPer100g! * factor,
      sodiumMg: food.sodiumMgPer100g == null
          ? null
          : food.sodiumMgPer100g! * factor,
      food: food,
      foodName: food.name,
      source: source ?? 'self',
    );
  }

  FoodLogEntry _entryFromLog(FoodLogEntry entry, {String? source}) {
    return FoodLogEntry(
      id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
      date: widget.date,
      loggedAt: _defaultLoggedAt(),
      servingGrams: entry.servingGrams,
      calories: entry.calories,
      proteinGrams: entry.proteinGrams,
      carbsGrams: entry.carbsGrams,
      fatGrams: entry.fatGrams,
      fiberGrams: entry.fiberGrams,
      sugarGrams: entry.sugarGrams,
      sodiumMg: entry.sodiumMg,
      food: entry.food,
      foodName: entry.foodName ?? entry.food?.name,
      portionLabel: entry.portionLabel,
      source: source ?? entry.source,
    );
  }

  // --- favorites ---

  Future<void> _toggleFavoriteFood(Food food) async {
    final repo = GetIt.instance<FoodRepository>();
    final wasFavorite = _favoriteIds.contains(food.id);
    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(food.id);
        _favoriteFoods.removeWhere((f) => f.id == food.id);
      } else {
        _favoriteIds.add(food.id);
        _favoriteFoods.insert(0, food);
        if (_favoriteFoods.length > 10) {
          _favoriteFoods.removeRange(10, _favoriteFoods.length);
        }
      }
    });
    try {
      if (wasFavorite) {
        await repo.removeFavorite(food.id);
      } else {
        await repo.addFavorite(food.id);
      }
    } catch (_) {
      if (!mounted) return;
      // Roll back on failure.
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(food.id);
          _favoriteFoods.insert(0, food);
          if (_favoriteFoods.length > 10) {
            _favoriteFoods.removeRange(10, _favoriteFoods.length);
          }
        } else {
          _favoriteIds.remove(food.id);
          _favoriteFoods.removeWhere((f) => f.id == food.id);
        }
      });
    }
  }

  // --- staging / logging ---

  /// Routes [entries] to the plate (default) or straight to the day, depending
  /// on [AddFoodSheet.enablePlate].
  ///
  /// - Plate mode: stages the entries into [_plate] (revealing the "Log foods"
  ///   bar) with NO `onAdd` and NO toast — the appearing bar is the feedback.
  /// - Immediate mode (`enablePlate == false`): logs the entries through
  ///   `onAdd` right away and confirms with a toast, keeping the sheet open so
  ///   several foods can be added in a row. This is the `/add-food` contract.
  void _addEntries(
    List<FoodLogEntry> entries, {
    String? name,
    bool skipAutoReview = false,
  }) {
    if (entries.isEmpty) return;
    if (widget.enablePlate) {
      setState(() => _plate.addAll(entries));
      // Context mode: surface the running plate after each stage so you can
      // tweak grams/items as you go. Speed mode (default) stays in search.
      // [skipAutoReview] lets the scan path open the review ITSELF (with the
      // scanned row highlighted + a banner) so we don't double-open here.
      if (_contextMode && mounted && !skipAutoReview) {
        _openPlateReview(context);
      }
      return;
    }
    widget.onAdd(List<FoodLogEntry>.unmodifiable(entries));
    if (!mounted) return;
    final label =
        name ??
        (entries.length == 1
            ? (entries.first.foodName ?? entries.first.food?.name ?? 'food')
            : '${entries.length} foods');
    HustlSnack.show(
      context,
      'Added $label.',
      variant: HustlSnackVariant.success,
    );
  }

  /// Commits the whole plate at once (plate mode only): fires `onAdd` for every
  /// staged entry, then closes the sheet and confirms with a toast. The router
  /// + messenger are captured before any await so a popped context can't break
  /// the close/confirm.
  Future<void> _commitPlate() async {
    if (_plate.isEmpty) return;
    final router = GoRouter.of(context);
    final entries = List<FoodLogEntry>.unmodifiable(_plate);
    widget.onAdd(entries);
    final label = entries.length == 1
        ? (entries.first.foodName ?? entries.first.food?.name ?? 'food')
        : '${entries.length} foods';
    if (router.canPop()) router.pop();
    if (!mounted) return;
    HustlSnack.show(
      context,
      'Logged $label.',
      variant: HustlSnackVariant.success,
    );
  }

  /// Opens the editable plate review. Edits flow back through `onChanged` so the
  /// parent `_plate` stays in sync even if the review is dismissed without
  /// committing; `onCommit` closes the review then commits the whole plate.
  Future<void> _openPlateReview(
    BuildContext context, {
    String? highlightEntryId,
    String? bannerMessage,
  }) async {
    await showPlateReview(
      context,
      entries: List<FoodLogEntry>.from(_plate),
      highlightEntryId: highlightEntryId,
      bannerMessage: bannerMessage,
      onChanged: (updated) {
        if (!mounted) return;
        setState(() {
          _plate
            ..clear()
            ..addAll(updated);
        });
      },
      onCommit: () {
        if (context.canPop()) context.pop();
        _commitPlate();
      },
    );
  }

  /// Adds a scanned (label / barcode) entry and, in plate mode, ALWAYS opens the
  /// plate review with the scanned row highlighted + a "review the portion"
  /// banner — regardless of speed/context mode — so the estimated portion is the
  /// first thing the user confirms. We stage with `skipAutoReview` so the
  /// context-mode auto-open in [_addEntries] doesn't double-open the review.
  ///
  /// In immediate mode (`enablePlate == false`, e.g. `/add-food`) there is no
  /// plate to review, so [_addEntries] logs the entry straight away with its
  /// usual confirmation toast.
  void _addScannedEntry(FoodLogEntry entry) {
    _addEntries([entry], skipAutoReview: true);
    if (!widget.enablePlate || !mounted) return;
    _openPlateReview(
      context,
      highlightEntryId: entry.id,
      bannerMessage: 'Scanned — review the portion before logging.',
    );
  }

  // --- add flows ---

  void _onAddFood(Food food, double grams) {
    if (grams <= 0) return;
    _addEntries([_entryFromFood(food, grams, source: 'search')]);
  }

  /// Quick-add fast path from the search results '+' affordance: logs the food
  /// at its default serving (its `servingSizeGrams`, or 100g when unset), then
  /// resets the query for the next pick while keeping focus in the search field.
  void _onQuickAddDefault(BuildContext blocContext, Food food) {
    final grams = food.servingSizeGrams ?? 100;
    if (grams <= 0) return;
    _addEntries([_entryFromFood(food, grams, source: 'search')]);
    _controller.clear();
    // Clearing the field text alone leaves the previous query's results under a
    // now-blank box; tell the bloc the query is empty so it resets to the empty
    // state and the stale results disappear with the cleared input.
    blocContext.read<FoodSearchBloc>().add(const FoodQueryChanged(''));
    if (mounted && !_searchFocus.hasFocus) {
      _searchFocus.requestFocus();
    }
  }

  Future<void> _onQuickAddTap(BuildContext context) async {
    final entry = await showDialog<FoodLogEntry>(
      context: context,
      builder: (context) => QuickAddDialog(
        date: widget.date,
        defaultLoggedAt: _defaultLoggedAt(),
      ),
    );
    if (!mounted || entry == null) return;
    _addEntries([entry]);
  }

  Future<void> _onRecipesTap(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.x2,
            right: AppSpacing.x2,
            top: AppSpacing.x2,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.x2,
          ),
          child: RecipesBrowser(
            date: widget.date,
            defaultLoggedAt: _defaultLoggedAt(),
            onPick: (entries) {
              sheetContext.pop();
              _addEntries(entries, name: 'recipe');
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onCopyFromDayTap(BuildContext context) async {
    final repo = GetIt.instance<FoodLogRepository>();
    final result = await CopyFromDaySheet.show(
      context,
      targetDate: widget.date,
      loadDay: repo.getLogsForDate,
    );
    if (!mounted || result == null || result.entries.isEmpty) return;
    _addEntries(
      result.entries.map((e) => _entryFromLog(e, source: 'copy')).toList(),
    );
  }

  // --- scan flows (all log immediately) ---

  Future<void> _openScanMenu(BuildContext context) async {
    final choice = await showAddFoodScanMenu(context);
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case AddFoodScanChoice.meal:
        await _onMealPhotoScanTap(context);
      case AddFoodScanChoice.barcode:
        await _onBarcodeTap(context);
      case AddFoodScanChoice.label:
        await _onLabelScanTap(context);
    }
  }

  Future<void> _onMealPhotoScanTap(BuildContext context) async {
    final result = await showDialog<MealPhotoScanResult>(
      context: context,
      builder: (context) => MealPhotoScanDialog(
        date: widget.date,
        primaryAction: MealPhotoScanAction.logMeal,
        // Tapping the camera shortcut means "scan a meal" — open the camera
        // immediately instead of landing on an intermediate "start camera" tap.
        autoStartCamera: true,
        defaultLoggedAt: _defaultLoggedAt(),
        dayTargetCalories: widget.dayTargetCalories,
        dayConsumedCalories: widget.dayConsumedCalories,
      ),
    );
    if (!mounted || result == null) return;
    // Prefer the per-item breakdown (richer diary); fall back to the single
    // combined meal entry when no breakdown is available.
    final entries = result.plateEntries.isNotEmpty
        ? result.plateEntries
        : [result.totalEntry];
    _addEntries(entries, name: result.totalEntry.foodName ?? 'meal');
  }

  /// Describe-a-meal: opens the AI scan dialog straight into its NL text entry
  /// (no camera). The estimate stages onto the plate like a photo scan.
  Future<void> _onDescribeTap(BuildContext context) async {
    final result = await showDialog<MealPhotoScanResult>(
      context: context,
      builder: (context) => MealPhotoScanDialog(
        date: widget.date,
        primaryAction: MealPhotoScanAction.logMeal,
        autoStartCamera: false,
        startInDescribe: true,
        defaultLoggedAt: _defaultLoggedAt(),
        dayTargetCalories: widget.dayTargetCalories,
        dayConsumedCalories: widget.dayConsumedCalories,
      ),
    );
    if (!mounted || result == null) return;
    final entries = result.plateEntries.isNotEmpty
        ? result.plateEntries
        : [result.totalEntry];
    _addEntries(entries, name: result.totalEntry.foodName ?? 'meal');
  }

  Future<void> _onLabelScanTap(BuildContext context) async {
    if (kIsWeb) {
      HustlSnack.show(
        context,
        'Label scan isn\'t available on web yet.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    final entry = await showDialog<FoodLogEntry>(
      context: context,
      builder: (context) => NutritionLabelScanDialog(
        date: widget.date,
        defaultLoggedAt: _defaultLoggedAt(),
      ),
    );
    if (!mounted || entry == null) return;
    _addScannedEntry(entry);
  }

  Future<String?> _promptBarcodeInput(BuildContext context) async {
    final textController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Barcode'),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(textController.text.trim()),
            child: const Text('Lookup'),
          ),
        ],
      ),
    );
    textController.dispose();
    return code?.trim().isEmpty == true ? null : code;
  }

  Future<void> _onBarcodeTap(BuildContext context) async {
    final repo = GetIt.instance<FoodRepository>();
    String? code;
    if (kIsWeb) {
      code = await _promptBarcodeInput(context);
    } else {
      final result = await showDialog<BarcodeScanResult>(
        context: context,
        builder: (_) => const BarcodeScanDialog(),
      );
      if (!context.mounted) return;
      switch (result) {
        case BarcodeScanCode(code: final scanned):
          code = scanned;
        case BarcodeScanManualEntry():
          code = await _promptBarcodeInput(context);
        case null:
          return;
      }
    }
    if (!context.mounted || code == null || code.isEmpty) return;
    try {
      final food = await repo.lookupBarcode(code);
      if (!context.mounted) return;
      if (food == null) {
        await _onBarcodeMissFallback(context);
        return;
      }
      // Seed at the product's default serving (matching the search quick-add);
      // the review opens highlighted so the user confirms the portion before
      // logging rather than fine-tuning later from the diary row.
      final grams = food.servingSizeGrams ?? 100;
      _addScannedEntry(_entryFromFood(food, grams, source: 'barcode'));
    } catch (e) {
      if (!context.mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      HustlSnack.show(
        context,
        message.trim().isEmpty
            ? 'Couldn’t look up that barcode. Please try again.'
            : message,
        variant: HustlSnackVariant.error,
      );
    }
  }

  /// Handles a barcode that isn't in any database.
  ///
  /// Instead of dead-ending on a "not found" message, we hand off to the label
  /// scan flow: the user photographs the product's nutrition panel, OCR fills
  /// the create-custom-food form, and they confirm.
  Future<void> _onBarcodeMissFallback(BuildContext context) async {
    if (kIsWeb) {
      HustlSnack.show(
        context,
        'No food found for that barcode. Try searching or add it manually.',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    HustlSnack.show(
      context,
      'No match for that barcode. Snap the nutrition label to add it.',
      variant: HustlSnackVariant.info,
    );
    final entry = await showDialog<FoodLogEntry>(
      context: context,
      builder: (context) => NutritionLabelScanDialog(
        date: widget.date,
        defaultLoggedAt: _defaultLoggedAt(),
      ),
    );
    if (!mounted || entry == null) return;
    _addScannedEntry(entry);
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = FoodSearchBloc(GetIt.instance<FoodRepository>());
        final initial = widget.initialQuery?.trim();
        if (!_seededInitialQuery && initial != null && initial.isNotEmpty) {
          _seededInitialQuery = true;
          bloc.add(FoodQueryChanged(initial));
        }
        return bloc;
      },
      child: Builder(
        builder: (innerContext) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                height: constraints.maxHeight,
                child: ResponsiveCenter(
                  maxContentWidth: 600,
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(
                      left: AppSpacing.x2,
                      right: AppSpacing.x2,
                      top: AppSpacing.x1 + 4,
                      bottom:
                          MediaQuery.of(innerContext).viewInsets.bottom +
                          AppSpacing.x2,
                    ),
                    child: Column(
                      children: [
                        _buildHeader(innerContext),
                        const SizedBox(height: AppSpacing.x1 + 4),
                        Expanded(
                          child: AddFoodSearchView(
                            controller: _controller,
                            focusNode: _searchFocus,
                            suggested: _suggested,
                            latest: _latestEntries(),
                            favorites: _favoriteFoods,
                            isFavorite: _isFavoriteFood,
                            onScan: () => _onMealPhotoScanTap(innerContext),
                            onAddFood: _onAddFood,
                            onAddLatest: (entry) => _addEntries([
                              _entryFromLog(entry, source: 'copy'),
                            ]),
                            onToggleFavorite: _toggleFavoriteFood,
                            onAddCustom: () => _onQuickAddTap(innerContext),
                            onAddDefault: (food) =>
                                _onQuickAddDefault(innerContext, food),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        AddFoodMethodRibbon(
                          onScan: () => _openScanMenu(innerContext),
                          onQuickAdd: () => _onQuickAddTap(innerContext),
                          onDescribe: () => _onDescribeTap(innerContext),
                          onRecipes: () => _onRecipesTap(innerContext),
                          onCopyDay: () => _onCopyFromDayTap(innerContext),
                        ),
                        if (widget.enablePlate && _plate.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.x1),
                          PlateBar(
                            entries: _plate,
                            onExpand: () => _openPlateReview(innerContext),
                            onCommit: _commitPlate,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: () => _closeSheet(context),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
        ),
        const SizedBox(width: 6),
        // Sheet header carries the screen-title voice (§12.2: 20/w700).
        Text('Add food', style: theme.textTheme.titleLarge),
        const Spacer(),
        // ODbL requires a durable, accessible credit for cached Open Food Facts
        // data — kept here behind a quiet ⓘ rather than a footer that crowded
        // the search surface.
        IconButton(
          onPressed: () => _showDataSources(context),
          icon: const Icon(Icons.info_outline),
          tooltip: 'Data sources',
        ),
        // Speed vs context: a quiet toggle (plate mode only). Speed stays in
        // search after each add; context auto-opens the plate review to tweak
        // as you go. Tinted on when context mode is active.
        if (widget.enablePlate)
          IconButton(
            onPressed: _toggleContextMode,
            isSelected: _contextMode,
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.fact_check_outlined),
            color: _contextMode ? theme.colorScheme.primary : null,
            tooltip: _contextMode
                ? 'Context: review the plate after each add'
                : 'Speed: stay in search after each add',
          ),
      ],
    );
  }

  /// The data-source credit, surfaced from the header ⓘ. ODbL requires a
  /// durable, accessible credit for cached Open Food Facts data; USDA FoodData
  /// Central is public domain but credited alongside for clarity.
  void _showDataSources(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x3,
          0,
          AppSpacing.x3,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data sources', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Branded food data comes from Open Food Facts, used under the '
              'Open Database License (ODbL). Generic foods come from USDA '
              'FoodData Central (public domain).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
