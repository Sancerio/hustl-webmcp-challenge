import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../domain/models/food_log_entry.dart';
import '../../domain/repositories/recipes_repository.dart';
import '../../domain/services/recipe_from_entries.dart';
import '../utils/macro_format.dart';
import 'food_plate.dart';
import 'plate_review_row.dart';
import 'recipe_name_dialog.dart';

/// Opens the editable plate review as a modal bottom sheet. The sheet edits a
/// working copy and reports every change through [onChanged] so the parent's
/// plate stays in sync even if the sheet is dismissed without committing.
/// [onCommit] fires when the user taps "Log foods (N)".
///
/// After a scan, pass [highlightEntryId] to tint + auto-expand the freshly
/// scanned row and [bannerMessage] to surface a "review the portion" banner so
/// the user lands on the portion they most likely need to adjust.
Future<void> showPlateReview(
  BuildContext context, {
  required List<FoodLogEntry> entries,
  required ValueChanged<List<FoodLogEntry>> onChanged,
  required VoidCallback onCommit,
  String? highlightEntryId,
  String? bannerMessage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (_) => PlateReviewSheet(
      entries: entries,
      onChanged: onChanged,
      onCommit: onCommit,
      highlightEntryId: highlightEntryId,
      bannerMessage: bannerMessage,
    ),
  );
}

/// A modal sheet listing the staged foods as editable rows: name + provenance
/// pill + macros + grams. Tapping a row (or its pencil) expands an inline
/// portion editor; the trailing X removes it (with Undo). A running-total row
/// sits above the commit / clear actions.
class PlateReviewSheet extends StatefulWidget {
  const PlateReviewSheet({
    super.key,
    required this.entries,
    required this.onChanged,
    required this.onCommit,
    this.highlightEntryId,
    this.bannerMessage,
  });

  final List<FoodLogEntry> entries;
  final ValueChanged<List<FoodLogEntry>> onChanged;
  final VoidCallback onCommit;

  /// When set, the matching row is briefly highlighted and auto-expanded so a
  /// just-scanned portion is immediately adjustable.
  final String? highlightEntryId;

  /// When set, a dismissible-on-scroll banner is shown at the top of the sheet.
  final String? bannerMessage;

  @override
  State<PlateReviewSheet> createState() => _PlateReviewSheetState();
}

class _PlateReviewSheetState extends State<PlateReviewSheet> {
  late List<FoodLogEntry> _items = List<FoodLogEntry>.from(widget.entries);

  /// The index of the row whose inline portion editor is open (only one at a
  /// time), or null when none is expanded.
  int? _editingIndex;

  /// Whether the highlight tint is currently painted; fades off after a beat.
  bool _highlightActive = false;
  Timer? _highlightTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-expand + highlight the scanned row so its portion is front-and-center.
    final id = widget.highlightEntryId;
    if (id != null) {
      final index = _items.indexWhere((e) => e.id == id);
      if (index >= 0) {
        _editingIndex = index;
        _highlightActive = true;
        // Let the tint linger briefly, then fade it via the row's AnimatedContainer.
        _highlightTimer = Timer(AppMotion.emphasized * 6, () {
          if (!mounted) return;
          setState(() => _highlightActive = false);
        });
        // Scanned entries are appended to the end of the plate, so on a long
        // plate the highlighted row starts below the fold. Once laid out, scroll
        // to it so the banner's "review the portion" target is actually on-screen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: AppMotion.emphasized,
            curve: Curves.easeOutCubic,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(List<FoodLogEntry>.unmodifiable(_items));

  /// Toggles the inline portion editor for [index]; only one row is open at a
  /// time, so opening one closes any other.
  void _toggleEdit(int index) {
    setState(() => _editingIndex = _editingIndex == index ? null : index);
  }

  /// Live re-portion as the row's stepper / chips move: proportionally rescales
  /// calories + all macros via the shared [rescaleEntryToGrams] (works for
  /// label/AI-scan rows with no linked Food) and re-syncs the parent.
  void _changeGrams(int index, double grams) {
    if (grams <= 0) return;
    setState(() => _items[index] = rescaleEntryToGrams(_items[index], grams));
    _emit();
  }

  void _remove(int index) {
    final removed = _items[index];
    setState(() {
      _items.removeAt(index);
      // Keep the open editor pointed at the right row after a removal shifts
      // indices (or close it if the open row itself was removed).
      if (_editingIndex == index) {
        _editingIndex = null;
      } else if (_editingIndex != null && _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });
    _emit();
    HustlSnack.show(
      context,
      'Removed ${removed.foodName ?? removed.food?.name ?? 'food'}.',
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() {
          final at = index <= _items.length ? index : _items.length;
          _items.insert(at, removed);
          // Reinserting shifts later rows down by one, so keep an open editor
          // pointed at the same food it was editing before the remove.
          if (_editingIndex != null && _editingIndex! >= at) {
            _editingIndex = _editingIndex! + 1;
          }
        });
        _emit();
      },
    );
  }

  void _clear() {
    final restore = List<FoodLogEntry>.from(_items);
    setState(() {
      _items.clear();
      _editingIndex = null;
    });
    _emit();
    HustlSnack.show(
      context,
      'Cleared the plate.',
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() => _items = restore);
        _emit();
      },
    );
  }

  /// Persists the current plate as a reusable recipe. Prompts for a name, maps
  /// the working items through the shared [recipeFromEntries], and saves. This
  /// is independent of logging — the sheet stays open so the user can still tap
  /// "Log foods (N)" afterwards.
  Future<void> _saveAsRecipe() async {
    if (_items.isEmpty) return;
    final name = await promptRecipeName(context);
    if (name == null || !mounted) return;

    final recipe = recipeFromEntries(name: name, entries: _items);
    try {
      await GetIt.instance<RecipesRepository>().createRecipe(recipe);
    } catch (_) {
      if (!mounted) return;
      HustlSnack.show(
        context,
        'Couldn’t save that recipe. Please try again.',
        variant: HustlSnackVariant.error,
      );
      return;
    }
    if (!mounted) return;
    HustlSnack.show(
      context,
      'Recipe saved.',
      variant: HustlSnackVariant.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _items.length;
    final totals = plateTotals(_items);
    final totalsLine = formatMacros(
      protein: totals.protein,
      fat: totals.fat,
      carbs: totals.carbs,
      calories: totals.calories,
    );
    final banner = widget.bannerMessage;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.x2,
        right: AppSpacing.x2,
        top: AppSpacing.x2,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.x2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Your plate', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (count > 0)
                TextButton(onPressed: _clear, child: const Text('Clear')),
            ],
          ),
          if (banner != null) ...[
            const SizedBox(height: AppSpacing.x1),
            _ReviewBanner(message: banner),
          ],
          const SizedBox(height: AppSpacing.x1),
          Flexible(
            child: ListView.separated(
              controller: _scrollController,
              shrinkWrap: true,
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => PlateReviewRow(
                entry: _items[i],
                isEditing: _editingIndex == i,
                highlighted:
                    _highlightActive && _items[i].id == widget.highlightEntryId,
                onToggleEdit: () => _toggleEdit(i),
                onGramsChanged: (g) => _changeGrams(i, g),
                onRemove: () => _remove(i),
              ),
            ),
          ),
          const Divider(height: AppSpacing.x3),
          Row(
            children: [
              Text('Total', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                totalsLine,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          FilledButton(
            onPressed: count == 0 ? null : widget.onCommit,
            child: Text('Log foods ($count)'),
          ),
          if (count > 0) ...[
            const SizedBox(height: AppSpacing.x1),
            OutlinedButton.icon(
              onPressed: _saveAsRecipe,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Save as recipe'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A short, theme-tokened banner shown at the top of the sheet after a scan,
/// nudging the user to confirm the estimated portion before logging.
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1 + 4,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.controlRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 18,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
