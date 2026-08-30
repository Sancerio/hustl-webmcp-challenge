import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import '../../../../core/services/nutrition_widget_service.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../../core/widgets/hustl_icon.dart';
import '../../../../core/widgets/hustl_snack.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../../../../core/widgets/screen_empty_state.dart';
import '../../domain/models/food_log_entry.dart';
import '../../domain/services/meal_clipboard.dart';
import '../../domain/services/recipe_from_entries.dart';
import '../../domain/repositories/food_log_repository.dart';
import '../../domain/repositories/nutrition_targets_repository.dart';
import '../../domain/repositories/recipes_repository.dart';
import '../bloc/diary_bloc.dart';
import '../bloc/diary_event.dart';
import '../bloc/diary_state.dart';
import '../diary_refresh_signal.dart';
import '../widgets/add_food_sheet.dart';
import '../widgets/copy_from_day_sheet.dart';
import '../widgets/diary_components.dart';
import '../widgets/diary_selection_bar.dart';
import '../widgets/diary_energy_balance_card.dart';
import '../widgets/diary_header.dart';
import '../widgets/diary_week_banner.dart';
import '../widgets/edit_food_entry_sheet.dart';
import '../widgets/nutrition_inline_states.dart';
import '../../../health_sync/presentation/widgets/health_connect_primer.dart';
import '../widgets/paste_day_picker_sheet.dart';
import '../widgets/recipe_name_dialog.dart';
import '../utils/weight_unit.dart';
import '../widgets/weigh_in_prompt_card.dart';
import '../widgets/weight_entry_sheet.dart';

/// Below this many entries we show a compact meal-section list; at or above it
/// the per-hour timeline earns its scroll cost.
const int _kTimelineThreshold = 3;

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late final DiaryBloc _bloc;
  final _scrollController = ScrollController();
  final _currentHourKey = GlobalKey();
  final _repo = GetIt.instance<NutritionTargetsRepository>();
  DiaryRefreshSignal? _refreshSignal;

  String? _weighInPromptDismissedDay;
  WeightUnit? _weightUnit;
  bool _showJumpToNow = false;
  bool _energyShowExpenditure = false;

  // Multi-select state (MacroFactor-style retroactive "save a meal"). Selection
  // mode is an additive overlay on the existing diary rows; the ids index into
  // the live bloc entries for the day in view.
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  // Cached energy-balance future keyed on the day so date changes reuse the
  // result instead of flashing a loading state. The same future feeds the
  // week banner's consumption fills — zero extra fetches.
  Future<Map<String, dynamic>>? _energyFuture;
  String? _energyKey;

  @override
  void initState() {
    super.initState();
    _bloc = DiaryBloc(GetIt.instance<FoodLogRepository>(), _repo)
      ..add(LoadDiary(DateTime.now()));
    _loadWeighInPromptPrefs();
    _resolveWeightUnit();
    _scrollController.addListener(_onScroll);
    // Reload when a food is logged outside this screen's own bloc — notably the
    // global one-tap "/add-food" flow, which persists straight through the
    // repository while this kept-alive screen sits in the shell's IndexedStack.
    final getIt = GetIt.instance;
    if (getIt.isRegistered<DiaryRefreshSignal>()) {
      _refreshSignal = getIt<DiaryRefreshSignal>()
        ..addListener(_onExternalRefresh);
    }
  }

  @override
  void dispose() {
    _refreshSignal?.removeListener(_onExternalRefresh);
    _bloc.close();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Reload the day currently in view after an out-of-band log (e.g. the global
  /// add-food flow) so the diary reflects the new entry without a manual pull.
  void _onExternalRefresh() {
    if (!mounted) return;
    _bloc.add(LoadDiary(_bloc.state.date));
  }

  String _dayKey(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().substring(0, 10);

  bool _isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  Future<Map<String, dynamic>> _energyFutureFor(DateTime date) {
    final key = _dayKey(date);
    if (_energyKey == key && _energyFuture != null) return _energyFuture!;
    final end = DateTime(date.year, date.month, date.day);
    final start = end.subtract(const Duration(days: 29));
    _energyKey = key;
    _energyFuture = _repo.getInsights(start, end);
    return _energyFuture!;
  }

  void _onScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.position.pixels > 140;
    if (shouldShow == _showJumpToNow) return;
    setState(() => _showJumpToNow = shouldShow);
  }

  void _jumpToNow() {
    final ctx = _currentHourKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppMotion.slow,
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  Future<void> _loadWeighInPromptPrefs() async {
    final prefs = GetIt.instance<PreferencesService>();
    final dismissed = await prefs.getNutritionWeighInPromptDismissedDay();
    if (!mounted) return;
    setState(() => _weighInPromptDismissedDay = dismissed);
  }

  Future<void> _resolveWeightUnit() async {
    final u = await GetIt.instance<PreferencesService>().getWeightUnit();
    if (!mounted) return;
    setState(() => _weightUnit = WeightUnit(u));
  }

  Future<void> _dismissWeighInPromptForDay(DateTime date) async {
    final day = _dayKey(date);
    final prefs = GetIt.instance<PreferencesService>();
    await prefs.setNutritionWeighInPromptDismissedDay(day);
    if (!mounted) return;
    setState(() => _weighInPromptDismissedDay = day);
  }

  void _openAddFood(
    BuildContext context,
    DateTime date, {
    String? initialQuery,
    DateTime? initialLoggedAt,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) => AddFoodSheet(
        date: date,
        initialQuery: initialQuery,
        initialLoggedAt: initialLoggedAt,
        dayTargetCalories: _bloc.state.targets?.caloriesTarget,
        dayConsumedCalories: _bloc.state.totalCalories,
        onAdd: (entries) => _bloc.add(AddDiaryEntries(entries)),
      ),
    );
  }

  void _openEditEntry(BuildContext context, FoodLogEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) => EditFoodEntrySheet(
        entry: entry,
        onSave: (patch) => _saveEntryEdit(entry, patch),
      ),
    );
  }

  /// Applies an edit patch. When the patch RE-DATES the entry to a different
  /// day, we stay on the current day and surface a "Moved to <date>." snack with
  /// an Undo that re-patches the entry back to its original day.
  void _saveEntryEdit(FoodLogEntry entry, Map<String, dynamic> patch) {
    final originalDay = _dayKey(entry.date);
    final newDay = patch['date'] as String?;
    _bloc.add(UpdateDiaryEntry(entry.id, patch));
    if (newDay == null || newDay == originalDay) return;

    final movedTo = DateTime.parse(newDay);
    HustlSnack.show(
      context,
      'Moved to ${DateFormat('EEE, MMM d').format(movedTo)}.',
      actionLabel: 'Undo',
      onAction: () =>
          _bloc.add(UpdateDiaryEntry(entry.id, {'date': originalDay})),
    );
  }

  /// Deletes the entry and surfaces an Undo toast that re-logs it — a swipe is
  /// easy to trigger by accident, so deletion should never be a dead-end.
  void _deleteWithUndo(String id, List<FoodLogEntry> entries) {
    FoodLogEntry? removed;
    for (final e in entries) {
      if (e.id == id) {
        removed = e;
        break;
      }
    }
    _bloc.add(DeleteDiaryEntry(id));
    if (removed == null) return;
    final entry = removed;
    HustlSnack.show(
      context,
      'Entry deleted.',
      actionLabel: 'Undo',
      onAction: () => _bloc.add(AddDiaryEntries([entry])),
    );
  }

  // --- selection mode (turn logged foods into a recipe) ---

  void _enterSelection([String? preselectId]) {
    Haptics.selection();
    setState(() {
      _selectionMode = true;
      if (preselectId != null) _selectedIds.add(preselectId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    Haptics.selection();
    setState(() {
      _selectedIds.contains(id)
          ? _selectedIds.remove(id)
          : _selectedIds.add(id);
    });
  }

  /// Header tap: select the whole group, or clear it when already all selected.
  void _toggleGroup(List<String> ids) {
    Haptics.selection();
    final allSelected = ids.every(_selectedIds.contains);
    setState(() {
      allSelected ? _selectedIds.removeAll(ids) : _selectedIds.addAll(ids);
    });
  }

  DiarySelection _selection() => DiarySelection(
    active: _selectionMode,
    selectedIds: _selectedIds,
    onToggle: _toggleSelected,
    onToggleGroup: _toggleGroup,
    onEnter: _enterSelection,
  );

  List<FoodLogEntry> _selectedEntries(List<FoodLogEntry> entries) =>
      entries.where((e) => _selectedIds.contains(e.id)).toList();

  /// Builds a self-contained [Recipe] from the chosen entries (one [RecipeItem]
  /// per entry, snapshotting every macro) and persists it. On success exits
  /// selection mode; both outcomes surface a [HustlSnack].
  Future<void> _createRecipeFromSelection(List<FoodLogEntry> entries) async {
    final selected = _selectedEntries(entries);
    if (selected.isEmpty) return;
    final name = await promptRecipeName(context);
    if (name == null || !mounted) return;

    // One source of truth for entry → Recipe mapping (shared with the plate's
    // "save as recipe").
    final recipe = recipeFromEntries(name: name, entries: selected);

    try {
      await GetIt.instance<RecipesRepository>().createRecipe(recipe);
    } catch (_) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn’t create that recipe. Please try again.',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    if (!mounted) return;
    _exitSelection();
    HustlSnack.show(
      context,
      'Recipe created.',
      variant: HustlSnackVariant.success,
    );
  }

  /// Bulk "Copy to…" for the current selection. Offers a quick "Today" choice
  /// plus a "Pick a date…" calendar; on a chosen date it copies each selected
  /// entry onto that day (fresh ids, macros + time-of-day preserved) and exits
  /// selection. Reuses the same add-on-date path as the per-row copy flow.
  Future<void> _copySelectionToDate(List<FoodLogEntry> entries) async {
    final selected = _selectedEntries(entries);
    if (selected.isEmpty) return;
    final target = await _pickCopyTarget();
    if (target == null || !mounted) return;
    await _copySelectedToDate(selected, _dayOnly(target));
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Small choice sheet for "Copy to…": a quick "Today" row plus a calendar.
  /// Returns the chosen target date, or null if dismissed.
  Future<DateTime?> _pickCopyTarget() {
    return showModalBottomSheet<DateTime>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x1,
                AppSpacing.x3,
                AppSpacing.x1,
              ),
              child: Text(
                'Copy to which day?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Today'),
              onTap: () {
                Haptics.selection();
                sheetContext.pop(DateTime.now());
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Pick a date…'),
              onTap: () async {
                final picked = await _pickArbitraryCopyDate();
                if (sheetContext.mounted) sheetContext.pop(picked);
              },
            ),
            const SizedBox(height: AppSpacing.x1),
          ],
        ),
      ),
    );
  }

  /// Opens a themed month calendar for "Copy to…". The window mirrors the diary
  /// date picker — two years back to a year ahead — so back-filling and week
  /// planning both work. Returns null if dismissed.
  Future<DateTime?> _pickArbitraryCopyDate() {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: _bloc.state.date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
  }

  /// Copies the [selected] entries onto [to] (snapshot per entry, fresh id, the
  /// 'copy' source badge, time-of-day preserved on the target date), exits
  /// selection, then confirms with a dated snackbar + Undo. Additive — the
  /// originals are never touched. Reuses [_copyEntryToDate] / addEntries — the
  /// same log-on-date path as the per-day copy flows.
  Future<void> _copySelectedToDate(
    List<FoodLogEntry> selected,
    DateTime to,
  ) async {
    final repo = GetIt.instance<FoodLogRepository>();
    final snapshots = [
      for (final entry in selected) _copyEntryToDate(entry, to),
    ];
    List<FoodLogEntry> inserted;
    try {
      inserted = await repo.addEntries(snapshots);
    } catch (_) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn’t copy those foods. Please try again.',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    if (!mounted) return;
    _exitSelection();
    if (_isSameDay(to, _bloc.state.date)) _bloc.add(LoadDiary(to));
    final count = inserted.length;
    if (count == 0) {
      HustlSnack.show(context, 'Nothing to copy.');
      return;
    }
    final dateLabel = _copyTargetLabel(to);
    HustlSnack.show(
      context,
      'Copied $count ${count == 1 ? 'item' : 'items'} to $dateLabel.',
      actionLabel: 'Undo',
      onAction: () async {
        for (final entry in inserted) {
          await repo.deleteEntry(entry.id);
        }
        if (mounted && _isSameDay(to, _bloc.state.date)) {
          _bloc.add(LoadDiary(to));
        }
      },
    );
  }

  /// Human-friendly target-day label for the copy confirmation: "today" /
  /// "tomorrow" / "yesterday", else a sentence-case date.
  String _copyTargetLabel(DateTime date) {
    final today = _dayOnly(DateTime.now());
    final diff = _dayOnly(date).difference(today).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    if (diff == -1) return 'yesterday';
    final pattern = date.year == today.year ? 'EEE, MMM d' : 'EEE, MMM d, y';
    return DateFormat(pattern).format(date);
  }

  // --- copy a day ---

  Widget _buildDayMenu(DateTime date) {
    final entries = _bloc.state.entries;
    final clipboard = MealClipboard.instance;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Day options',
      onSelected: (value) {
        if (value == 'repeat') {
          _copyDay(date.subtract(const Duration(days: 1)), date);
        } else if (value == 'copy') {
          _openCopyFromDay(date);
        } else if (value == 'select') {
          _enterSelection();
        } else if (value == 'copyDay') {
          _copyDayToClipboard(date, entries);
        } else if (value == 'pasteDay') {
          _pasteDay(date);
        }
      },
      itemBuilder: (context) => [
        if (entries.isNotEmpty)
          const PopupMenuItem(value: 'select', child: Text('Select foods')),
        const PopupMenuItem(value: 'repeat', child: Text('Repeat yesterday')),
        const PopupMenuItem(
          value: 'copy',
          child: Text('Copy from another day'),
        ),
        if (entries.isNotEmpty)
          const PopupMenuItem(value: 'copyDay', child: Text('Copy day')),
        if (clipboard.hasContent)
          const PopupMenuItem(value: 'pasteDay', child: Text('Paste day')),
      ],
    );
  }

  /// Snapshots the day in view onto the [MealClipboard] for later pasting onto
  /// one or many future days (MacroFactor-style week planning).
  void _copyDayToClipboard(DateTime date, List<FoodLogEntry> entries) {
    if (entries.isEmpty) return;
    MealClipboard.instance.copy(entries, sourceDate: date);
    final n = entries.length;
    HustlSnack.show(context, 'Day copied — $n ${n == 1 ? 'food' : 'foods'}.');
  }

  /// Opens the multi-date picker, then writes the clipboard snapshot onto every
  /// chosen day (re-stamped to each target date with fresh ids, additive).
  Future<void> _pasteDay(DateTime fromDate) async {
    final clipboard = MealClipboard.instance;
    if (!clipboard.hasContent) return;
    final source = clipboard.entries;
    final targets = await PasteDayPickerSheet.show(
      context,
      fromDate: fromDate,
      foodCount: source.length,
    );
    if (targets == null || targets.isEmpty || !mounted) return;

    final repo = GetIt.instance<FoodLogRepository>();
    final snapshots = [
      for (final target in targets)
        for (final entry in source) _copyEntryToDate(entry, target),
    ];
    try {
      await repo.addEntries(snapshots);
    } catch (_) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn’t paste those foods. Please try again.',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    if (!mounted) return;
    // Refresh if the day in view was one of the targets.
    if (targets.any((t) => _isSameDay(t, _bloc.state.date))) {
      _bloc.add(LoadDiary(_bloc.state.date));
    }
    final n = targets.length;
    HustlSnack.show(context, 'Pasted to $n ${n == 1 ? 'day' : 'days'}.');
  }

  Future<void> _openCopyFromDay(DateTime targetDate) async {
    final repo = GetIt.instance<FoodLogRepository>();
    final result = await CopyFromDaySheet.show(
      context,
      targetDate: targetDate,
      loadDay: repo.getLogsForDate,
    );
    if (result == null || result.entries.isEmpty) return;
    await _copySelected(result.entries, targetDate);
  }

  /// Adds the [source] entries (the items the user checked) onto [to], snapshot
  /// per entry with a fresh id, the 'copy' source badge, and the original
  /// time-of-day preserved on the target date. Additive — never replaces.
  Future<void> _copySelected(List<FoodLogEntry> source, DateTime to) async {
    final repo = GetIt.instance<FoodLogRepository>();
    final snapshots = [for (final entry in source) _copyEntryToDate(entry, to)];
    List<FoodLogEntry> inserted;
    try {
      inserted = await repo.addEntries(snapshots);
    } catch (_) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn’t copy those foods. Please try again.',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    if (!mounted) return;
    _bloc.add(LoadDiary(to));
    final count = inserted.length;
    if (count == 0) {
      HustlSnack.show(context, 'Nothing to copy.');
      return;
    }
    HustlSnack.show(
      context,
      'Copied $count ${count == 1 ? 'item' : 'items'}.',
      actionLabel: 'Undo',
      onAction: () async {
        for (final entry in inserted) {
          await repo.deleteEntry(entry.id);
        }
        if (mounted) _bloc.add(LoadDiary(to));
      },
    );
  }

  FoodLogEntry _copyEntryToDate(FoodLogEntry entry, DateTime to) {
    final local = entry.loggedAt.toLocal();
    return FoodLogEntry(
      id: 'temp-copy-${entry.id}-${DateTime.now().microsecondsSinceEpoch}',
      date: DateTime(to.year, to.month, to.day),
      loggedAt: DateTime(
        to.year,
        to.month,
        to.day,
        local.hour,
        local.minute,
        local.second,
      ),
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
      source: 'copy',
    );
  }

  Future<void> _copyDay(
    DateTime from,
    DateTime to, {
    bool replace = false,
  }) async {
    final repo = GetIt.instance<FoodLogRepository>();
    List<FoodLogEntry> inserted;
    try {
      inserted = await repo.copyDay(from, to, replaceExisting: replace);
    } catch (_) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn’t copy that day. Please try again.',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    if (!mounted) return;
    _bloc.add(LoadDiary(to));
    final count = inserted.length;
    if (count == 0) {
      HustlSnack.show(context, 'Nothing to copy from that day.');
      return;
    }
    if (replace) {
      // Replace cleared the target day's originals, so they can't be restored —
      // confirm without an undo affordance.
      HustlSnack.show(
        context,
        'Replaced with $count ${count == 1 ? 'item' : 'items'}.',
      );
      return;
    }
    HustlSnack.show(
      context,
      'Copied $count ${count == 1 ? 'item' : 'items'}.',
      actionLabel: 'Undo',
      onAction: () async {
        for (final entry in inserted) {
          await repo.deleteEntry(entry.id);
        }
        if (mounted) _bloc.add(LoadDiary(to));
      },
    );
  }

  Future<void> _openWeightEntry(BuildContext context) async {
    // Value-timed: before the first weight-log, offer to connect Apple Health
    // (the only place the OS permission can be requested). Shows once; declining
    // proceeds straight to the manual entry below — never a dead-end.
    await maybeRunHealthConnectPrimer(context);
    if (!context.mounted) return;
    final date = _bloc.state.date;
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (context) => WeightEntrySheet(
        date: date,
        initialUnit: _weightUnit,
        onLogged: () => _bloc.add(LoadDiary(date)),
      ),
    );
  }

  void _goToDay(DateTime date) => _bloc.add(LoadDiary(date));

  void _goToToday() => _bloc.add(LoadDiary(DateTime.now()));

  /// Opens a month calendar to jump to any day. The floor is two years back and
  /// the ceiling is a year ahead so future-dating (week planning) stays open.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _bloc.state.date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null || !mounted) return;
    _goToDay(picked);
  }

  /// True for a brand-new diary: the initial fetch has *resolved*, there was no
  /// error, targets have never been set, and nothing has been logged. We greet
  /// these users with an inviting first-run prompt instead of an empty calorie
  /// ring (§ new-user polish).
  ///
  /// The `hasLoaded` gate is load-bearing: the bloc's pristine pre-fetch state
  /// also has no targets and no entries, so without it the setup prompt would
  /// flash for a returning user while their data is still in flight. We show a
  /// skeleton during that window instead (see [_isInitialLoading]).
  bool _isFirstRun(DiaryState state) =>
      state.hasLoaded &&
      state.errorMessage == null &&
      (state.targets == null || state.targets!.caloriesTarget <= 0) &&
      state.entries.isEmpty &&
      _isSameDay(state.date, DateTime.now());

  /// True while the very first diary fetch is still in flight: nothing has
  /// resolved yet ([DiaryState.hasLoaded] is false), there's no cached data to
  /// keep on screen, and no error to surface. This is the window that used to
  /// render the "set up your nutrition" prompt; we show a loading skeleton
  /// matching the loaded layout instead so a returning user never sees the
  /// setup copy before their data arrives.
  bool _isInitialLoading(DiaryState state) =>
      !state.hasLoaded &&
      state.errorMessage == null &&
      state.entries.isEmpty &&
      state.targets == null;

  void _openTargetsSetup() => context.push('/nutrition/strategy');

  /// The calorie ring + macros double as the entry to the Strategy screen (your
  /// targets + the nutrition coach). Its only other entry was a first-run prompt
  /// that disappears once targets exist, so the ring is now the durable way in.
  Widget _tappableDiaryHeader(DiaryState state) => InkWell(
    onTap: _openTargetsSetup,
    borderRadius: BorderRadius.circular(20),
    child: DiaryHeader(state: state),
  );

  bool _shouldRefreshNutritionWidget(DiaryState previous, DiaryState current) {
    if (current.isLoading) return false;
    if (!_isSameDay(current.date, DateTime.now())) return false;
    return previous.date != current.date ||
        previous.totalCalories != current.totalCalories ||
        previous.totalProtein != current.totalProtein ||
        previous.totalFat != current.totalFat ||
        previous.totalCarbs != current.totalCarbs ||
        previous.targets != current.targets;
  }

  void _refreshNutritionWidget() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<NutritionWidgetService>()) return;
    unawaited(
      getIt<NutritionWidgetService>().updateNutritionSummaryWidget().catchError(
        (Object error, StackTrace stackTrace) {
          dev.log(
            'Failed to refresh nutrition widget after diary update',
            name: 'DiaryScreen',
            error: error,
            stackTrace: stackTrace,
          );
        },
      ),
    );
  }

  /// Per-day consumed/target calorie ratios for the week banner, read from
  /// the cached 30-day insights payload with the selected day overridden by
  /// the live bloc totals.
  Map<String, double> _weekFillRatios(
    Map<String, dynamic>? insights,
    DiaryState state,
  ) {
    final ratios = <String, double>{};
    final energy = (insights?['energyBalance'] as Map?)
        ?.cast<String, dynamic>();
    final days = (energy?['days'] as List?) ?? const [];
    for (final raw in days) {
      if (raw is! Map) continue;
      final date = raw['date']?.toString();
      final intake = (raw['intakeCalories'] as num?)?.toDouble() ?? 0;
      final target = (raw['targetCalories'] as num?)?.toDouble() ?? 0;
      if (date == null || date.length < 10 || target <= 0) continue;
      ratios[date.substring(0, 10)] = intake / target;
    }
    final calTarget = state.targets?.caloriesTarget ?? 0;
    if (calTarget > 0) {
      ratios[_dayKey(state.date)] = state.totalCalories / calTarget;
    }
    return ratios;
  }

  Widget _weekBanner(DiaryState state) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _energyFutureFor(state.date),
      builder: (context, snapshot) => DiaryWeekBanner(
        date: state.date,
        onSelectDay: _goToDay,
        fillRatioByDay: _weekFillRatios(snapshot.data, state),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocProvider.value(
      value: _bloc,
      child: MainScaffold(
        // Hide the add FAB while multi-selecting: the sticky selection bar owns
        // the bottom edge and "add food" is not a selection-mode action.
        floatingActionButton: _selectionMode
            ? null
            : FloatingActionButton(
                heroTag: 'diary-add-food',
                onPressed: () {
                  Haptics.selection();
                  _openAddFood(context, _bloc.state.date);
                },
                tooltip: 'Add food',
                child: HustlIcon(
                  asset: 'assets/icons/ic_add.svg',
                  size: 24,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
        child: MultiBlocListener(
          listeners: [
            BlocListener<DiaryBloc, DiaryState>(
              listenWhen: _shouldRefreshNutritionWidget,
              listener: (_, __) => _refreshNutritionWidget(),
            ),
            // Leaving the day in view drops the selection — its ids index the
            // old day's entries, so carrying them forward would be meaningless.
            BlocListener<DiaryBloc, DiaryState>(
              listenWhen: (prev, curr) => prev.date != curr.date,
              listener: (_, __) {
                if (_selectionMode) _exitSelection();
              },
            ),
          ],
          child: BlocBuilder<DiaryBloc, DiaryState>(
            // Skip the isLoading=true flip so the tree is not rebuilt while
            // data is in-flight (old data stays visible). Still rebuild when
            // data arrives (isLoading false), the date changes, entries/targets
            // update, errors appear, or weight data changes.
            buildWhen: (prev, curr) =>
                prev.date != curr.date ||
                prev.entries != curr.entries ||
                prev.targets != curr.targets ||
                prev.errorMessage != curr.errorMessage ||
                prev.dayWeightKg != curr.dayWeightKg ||
                prev.latestWeightKg != curr.latestWeightKg ||
                prev.latestWeightDate != curr.latestWeightDate ||
                prev.totalCalories != curr.totalCalories ||
                prev.totalProtein != curr.totalProtein ||
                prev.totalCarbs != curr.totalCarbs ||
                prev.totalFat != curr.totalFat ||
                prev.hasLoaded != curr.hasLoaded ||
                // Surface the first-load skeleton the instant the initial fetch
                // starts (isLoading flips true before any data exists), and tear
                // it down again when that fetch resolves.
                (!curr.hasLoaded && prev.isLoading != curr.isLoading) ||
                (prev.isLoading && !curr.isLoading),
            builder: (context, state) {
              final isToday = _isSameDay(state.date, DateTime.now());
              // Wide viewports (landscape tablet / desktop) reflow the body
              // into two side-by-side columns inside one scroll. Below the
              // breakpoint the layout stays a single column, byte-for-byte.
              final isWide =
                  MediaQuery.sizeOf(context).width >=
                  ResponsiveCenter.wideBreakpoint;
              return RefreshIndicator(
                onRefresh: () async => _bloc.add(LoadDiary(state.date)),
                child: Stack(
                  children: [
                    CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Pinned date title; the week banner beneath it
                        // collapses as the log scrolls (§12.2).
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: DiaryWeekHeaderDelegate(
                            topPadding: MediaQuery.of(context).padding.top,
                            title: DiaryDateTitle(
                              date: state.date,
                              onToday: _goToToday,
                              onPickDate: _pickDate,
                              trailingAction: _buildDayMenu(state.date),
                            ),
                            banner: _weekBanner(state),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.x2,
                            AppSpacing.x2,
                            AppSpacing.x2,
                            96,
                          ),
                          sliver: _isInitialLoading(state)
                              ? SliverList(
                                  delegate: SliverChildListDelegate([
                                    const _DiaryFirstLoadSkeleton(),
                                  ]),
                                )
                              : _isFirstRun(state)
                              ? SliverList(
                                  delegate: SliverChildListDelegate([
                                    const SizedBox(height: AppSpacing.x4),
                                    _NutritionFirstRunPrompt(
                                      onSetTargets: _openTargetsSetup,
                                      onAddFood: () =>
                                          _openAddFood(context, state.date),
                                    ),
                                  ]),
                                )
                              : isWide
                              ? SliverToBoxAdapter(
                                  child: _buildWideBody(context, state),
                                )
                              : SliverList(
                                  delegate: SliverChildListDelegate([
                                    _tappableDiaryHeader(state),
                                    const SizedBox(height: AppSpacing.x2),
                                    if (_weightUnit != null &&
                                        !state.isLoading &&
                                        isToday &&
                                        state.dayWeightKg == null &&
                                        _weighInPromptDismissedDay !=
                                            _dayKey(state.date)) ...[
                                      WeighInPromptCard(
                                        latestWeightKg: state.latestWeightKg,
                                        latestWeightDate:
                                            state.latestWeightDate,
                                        unit: _weightUnit!,
                                        onLogTap: () =>
                                            _openWeightEntry(context),
                                        onDismissTap: () =>
                                            _dismissWeighInPromptForDay(
                                              state.date,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.x2),
                                    ],
                                    if (state.isLoading &&
                                        state.entries.isEmpty)
                                      AppSkeleton.lines(rows: 5)
                                    else
                                      _buildLog(state),
                                    if (state.errorMessage != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: AppSpacing.x1,
                                        ),
                                        child: NutritionInlineError(
                                          title: 'Couldn’t load your diary',
                                          detail: state.errorMessage,
                                          onRetry: () =>
                                              _bloc.add(LoadDiary(state.date)),
                                        ),
                                      ),
                                    const SizedBox(height: AppSpacing.x2),
                                    _EnergyBalanceSection(
                                      future: _energyFutureFor(state.date),
                                      showExpenditure: _energyShowExpenditure,
                                      onToggle: (v) => setState(
                                        () => _energyShowExpenditure = v,
                                      ),
                                    ),
                                  ]),
                                ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: AppSpacing.x2,
                      bottom: MediaQuery.of(context).padding.bottom + 88,
                      child: _JumpToNowPill(
                        visible: _showJumpToNow && isToday && !_selectionMode,
                        onTap: _jumpToNow,
                      ),
                    ),
                    if (_selectionMode)
                      Positioned(
                        left: AppSpacing.x2,
                        right: AppSpacing.x2,
                        bottom:
                            MediaQuery.of(context).padding.bottom +
                            AppSpacing.x2,
                        child: DiarySelectionBar(
                          selectedCount: _selectedIds.length,
                          selectedCalories: _selectedEntries(
                            state.entries,
                          ).fold(0.0, (sum, e) => sum + e.calories),
                          onCreateRecipe: () =>
                              _createRecipeFromSelection(state.entries),
                          onCopyTo: () => _copySelectionToDate(state.entries),
                          onCancel: _exitSelection,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Wide-viewport (>= 900) two-column reflow of the diary body. The hero ring
  /// + macros, the weigh-in prompt, and the energy-balance summary stack in the
  /// LEFT column; the meal log/timeline (and any error line) fills the RIGHT
  /// column. Both columns live inside the single page scroll — this is just one
  /// [SliverToBoxAdapter] child — so the FAB and pinned week header are
  /// untouched. Below 900 this method is never called and the original
  /// single-column sliver renders byte-for-byte.
  Widget _buildWideBody(BuildContext context, DiaryState state) {
    final isToday = _isSameDay(state.date, DateTime.now());

    final leftColumn = <Widget>[
      _tappableDiaryHeader(state),
      if (_weightUnit != null &&
          !state.isLoading &&
          isToday &&
          state.dayWeightKg == null &&
          _weighInPromptDismissedDay != _dayKey(state.date)) ...[
        const SizedBox(height: AppSpacing.x2),
        WeighInPromptCard(
          latestWeightKg: state.latestWeightKg,
          latestWeightDate: state.latestWeightDate,
          unit: _weightUnit!,
          onLogTap: () => _openWeightEntry(context),
          onDismissTap: () => _dismissWeighInPromptForDay(state.date),
        ),
      ],
      const SizedBox(height: AppSpacing.x2),
      _EnergyBalanceSection(
        future: _energyFutureFor(state.date),
        showExpenditure: _energyShowExpenditure,
        onToggle: (v) => setState(() => _energyShowExpenditure = v),
      ),
    ];

    final rightColumn = <Widget>[
      if (state.isLoading && state.entries.isEmpty)
        AppSkeleton.lines(rows: 5)
      else
        _buildLog(state),
      if (state.errorMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.x1),
          child: NutritionInlineError(
            title: 'Couldn’t load your diary',
            detail: state.errorMessage,
            onRetry: () => _bloc.add(LoadDiary(state.date)),
          ),
        ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: leftColumn,
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rightColumn,
          ),
        ),
      ],
    );
  }

  Widget _buildLog(DiaryState state) {
    final entries = state.entries;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
        child: Column(
          children: [
            ScreenEmptyState(
              icon: Icons.restaurant_outlined,
              assetIcon: 'assets/icons/empty_nutrition.svg',
              title: 'Nothing logged yet',
              message: _isSameDay(state.date, DateTime.now())
                  ? 'Search a food or snap a photo to start your day.'
                  : 'No foods were logged on this day.',
              actionLabel: 'Add food',
              onAction: () => _openAddFood(context, state.date),
            ),
            const SizedBox(height: AppSpacing.x1),
            TextButton.icon(
              onPressed: () => _openCopyFromDay(state.date),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Copy from another day'),
            ),
          ],
        ),
      );
    }

    if (entries.length < _kTimelineThreshold) {
      return DiaryMealSections(
        entries: entries,
        onDelete: (id) => _deleteWithUndo(id, entries),
        onEdit: (entry) => _openEditEntry(context, entry),
        onAddToMeal: (hour) {
          final date = state.date;
          final at = DateTime(date.year, date.month, date.day, hour);
          _openAddFood(context, date, initialLoggedAt: at);
        },
        selection: _selection(),
      );
    }

    final entriesByHour = <int, List<FoodLogEntry>>{};
    for (final e in entries) {
      entriesByHour.putIfAbsent(e.loggedAt.toLocal().hour, () => []).add(e);
    }
    for (final hour in entriesByHour.keys) {
      entriesByHour[hour]!.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    }

    return DiaryTimeline(
      entriesByHour: entriesByHour,
      onDelete: (id) => _deleteWithUndo(id, entries),
      onEdit: (entry) => _openEditEntry(context, entry),
      onAddAtHour: (hour) {
        final date = state.date;
        final at = DateTime(date.year, date.month, date.day, hour);
        _openAddFood(context, date, initialLoggedAt: at);
      },
      currentHourKey: _currentHourKey,
      highlightCurrentHour: _isSameDay(state.date, DateTime.now()),
      selection: _selection(),
    );
  }
}

/// A quiet raised pill that scrolls the timeline back to the current hour.
class _JumpToNowPill extends StatelessWidget {
  const _JumpToNowPill({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.medium,
        curve: Curves.easeOut,
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: StadiumBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x1 + 4,
                vertical: AppSpacing.x1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text('Jump to now', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hosts the cached energy-balance future and keeps the last data on screen
/// while a new day loads (no flash-to-skeleton on date change).
class _EnergyBalanceSection extends StatelessWidget {
  const _EnergyBalanceSection({
    required this.future,
    required this.showExpenditure,
    required this.onToggle,
  });

  final Future<Map<String, dynamic>> future;
  final bool showExpenditure;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        // The diary only shows the energy summary inline; the full Insights
        // screen (the hub that also links to Strategy + Weight) was orphaned, so
        // give it a clear way in from here.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DiaryEnergyBalanceCard(
              insights: snapshot.data,
              showExpenditure: showExpenditure,
              onToggle: onToggle,
            ),
            // Left-aligned on purpose: the diary floats a "Jump to now" pill and
            // the add FAB in the bottom-RIGHT, so a right-aligned link here
            // collides with them as the section scrolls. Keep it on the left,
            // clear of the floating controls.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push('/nutrition/insights'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View insights'),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The diary's initial-load placeholder. Mirrors the loaded layout — a hero
/// card stand-in (the calorie ring + macro bars area) followed by a few log
/// rows — so a returning user sees a calm skeleton settling into their data,
/// never the "set up your nutrition" prompt, while the first fetch is in
/// flight. Built entirely from [AppSkeleton], so it shimmers like every other
/// loading surface and goes static under reduce-motion. Colors come from the
/// theme; nothing is hard-coded.
class _DiaryFirstLoadSkeleton extends StatelessWidget {
  const _DiaryFirstLoadSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading your nutrition',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero card stand-in: matches the elevated calorie ring + macros card.
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Column(
              children: [
                // The calorie ring.
                const AppSkeleton.circle(size: 132),
                const SizedBox(height: AppSpacing.x3),
                // Three macro bars (protein / carbs / fat).
                Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.x2),
                      const Expanded(child: AppSkeleton(height: 36)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          // Log rows stand-in.
          AppSkeleton.lines(rows: 4),
        ],
      ),
    );
  }
}

/// The nutrition first-run welcome (Wave I — Apple Fitness+ x Whoop): shown the
/// very first time the diary opens, before any targets exist. A soft elevated
/// card with a blue-tinted icon holder, a confident sentence-case headline, one
/// warm supportive line, and a blue [FilledButton] that opens the existing
/// targets/goal setup. A brand-new user lands on an invitation, not a blank
/// diary. The entrance fade/rise is skipped under reduce-motion.
class _NutritionFirstRunPrompt extends StatelessWidget {
  const _NutritionFirstRunPrompt({
    required this.onSetTargets,
    required this.onAddFood,
  });

  final VoidCallback onSetTargets;
  final VoidCallback onAddFood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3,
        AppSpacing.x4,
        AppSpacing.x3,
        AppSpacing.x3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Soft blue-tinted circular holder for a single clean glyph.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.restaurant_rounded,
              size: 30,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.x2 + 4),
          Text(
            'Let’s set up your nutrition',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x1 + 2),
          Text(
            'Pick a goal and we’ll set daily calorie and macro targets for you. '
            'You can fine-tune them anytime.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Haptics.selection();
                onSetTargets();
              },
              child: const Text('Set my targets'),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          TextButton(
            onPressed: () {
              Haptics.selection();
              onAddFood();
            },
            child: const Text('Just log a food for now'),
          ),
        ],
      ),
    );

    if (reduceMotion) return card;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: card,
    );
  }
}
