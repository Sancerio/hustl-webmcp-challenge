import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hustl_app/app/demo/demo_mode.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/core/widgets/hustl_icon.dart';

import '../../domain/models/food.dart';
import '../../domain/models/food_log_entry.dart';
import '../utils/go_to_ranking.dart';
import '../utils/history_food_match.dart';
import '../utils/macro_format.dart';
import 'food_glyph.dart';
import '../bloc/food_search_bloc.dart';
import '../bloc/food_search_event.dart';
import '../bloc/food_search_state.dart';
import 'add_food_portion_stepper.dart';
import 'food_quick_strip.dart';
import 'nutrition_inline_states.dart';

/// Search panel: a search field over favorites + recents as the empty-state
/// suggestions. Once a query is typed those are hidden and only live results
/// (or a no-match row) show. Tapping a food expands an inline portion stepper
/// instead of opening a modal grams dialog.
class AddFoodSearchView extends StatefulWidget {
  const AddFoodSearchView({
    super.key,
    required this.controller,
    required this.focusNode,
    this.suggested = const [],
    required this.latest,
    required this.favorites,
    required this.isFavorite,
    required this.onAddFood,
    required this.onAddLatest,
    required this.onToggleFavorite,
    this.onAddCustom,
    this.onAddDefault,
    this.onScan,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// "Suggested for now": the foods the user usually logs around this time of
  /// day. Merged INTO the Recent quick-pick strip — shown FIRST (the most
  /// time-relevant picks, each marked with a subtle sparkle), then recents,
  /// deduped by the food key. Populated only when non-empty (the backend's
  /// min-history guards suppress it otherwise); when empty the strip is just
  /// recents.
  final List<FoodLogEntry> suggested;

  /// Recently logged entries (recents) shown above search results.
  final List<FoodLogEntry> latest;
  final List<Food> favorites;
  final bool Function(Food) isFavorite;

  /// Commit a food at the chosen grams.
  final void Function(Food food, double grams) onAddFood;

  /// Quick-add fast path: log a result at its default serving in one tap,
  /// without expanding the inline stepper or leaving the search view. When null,
  /// the quick-add '+' affordance is hidden.
  final ValueChanged<Food>? onAddDefault;

  /// Re-log a previous entry directly.
  final ValueChanged<FoodLogEntry> onAddLatest;
  final ValueChanged<Food> onToggleFavorite;

  /// Opens the manual quick-add flow, offered when a query has no matches so a
  /// missing food is never a dead end.
  final VoidCallback? onAddCustom;

  /// A single TAP on the field's camera icon jumps straight into the meal-photo
  /// scan with the camera already opening — no menu, no second tap. The rarer
  /// barcode/label flows live on the method ribbon's Scan chip instead, so the
  /// field icon stays a one-purpose shortcut. Null hides the icon.
  final VoidCallback? onScan;

  @override
  State<AddFoodSearchView> createState() => _AddFoodSearchViewState();
}

class _AddFoodSearchViewState extends State<AddFoodSearchView> {
  Timer? _debounce;
  String? _expandedFoodId;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(BuildContext blocContext, String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      blocContext.read<FoodSearchBloc>().add(FoodQueryChanged(value));
    });
  }

  void _toggleExpanded(String id) {
    setState(() => _expandedFoodId = _expandedFoodId == id ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search for a food',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.onScan == null
                ? null
                // One plain tap → scan a meal (the camera opens straight away).
                // Barcode/label live on the ribbon's Scan chip, so the field
                // icon is a single-purpose shortcut with no hidden gesture.
                : IconButton(
                    onPressed: widget.onScan,
                    tooltip: 'Scan a meal',
                    icon: Icon(
                      Icons.photo_camera_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => _onChanged(context, v),
        ),
        const SizedBox(height: AppSpacing.x1 + 4),
        Expanded(
          child: BlocBuilder<FoodSearchBloc, FoodSearchState>(
            builder: (context, state) {
              if (state.isLoading) {
                return AppSkeleton.lines(rows: 5);
              }
              final query = widget.controller.text.trim();
              final hasQuery = query.isNotEmpty;
              final favorites = widget.favorites;
              final latest = widget.latest;
              final suggested = widget.suggested;

              // The empty-state landing splits the two past-food sources so they
              // never read as the same list twice:
              //   • the horizontal Recent strip = the plain recents (one-tap
              //     re-log, no vertical cost),
              //   • the vertical "[time-of-day] picks" list = the time-of-day
              //     SUGGESTIONS rendered as rich rows (icon, name, macros +
              //     serving, a trailing + add).
              // When suggestions are suppressed (thin history) the picks list
              // falls back to a tasteful prompt and the strip keeps carrying the
              // suggestion sparkle so the time-relevant picks are never lost.
              final hasPicks = suggested.isNotEmpty;
              // Strip: recents only when the vertical picks list carries the
              // suggestions; otherwise the legacy merged strip (suggestions,
              // then recents) so a thin-history user still gets the sparkle
              // chips. Capped to a sensible 8 either way.
              final timeOfDayPicks =
                  suggested.take(8).toList(growable: false);
              final quickPicks = hasPicks
                  ? _mergeQuickPicks(const [], latest)
                  : _mergeQuickPicks(suggested, latest);

              // History-first search: when a query is active, the user's own
              // logged foods that match the query rank FIRST — above the generic
              // catalog — because people re-eat the same things. The match is a
              // pure local transform over the recents/suggestions already in
              // memory, so it resolves INSTANTLY as you type (no network); the
              // catalog/backend rows (state.results) merge in behind it as they
              // arrive. A history food that's also in the catalog appears ONCE,
              // kept as the history row so re-logging pre-fills the user's
              // last-used serving + macros (carried via historyEntryToFood).
              final historyResults = hasQuery
                  ? historyMatches(query, suggested: suggested, latest: latest)
                  : const <Food>[];
              final mergedResults = hasQuery
                  ? mergeCatalogAfterHistory(
                      history: historyResults,
                      catalog: state.results,
                    )
                  : state.results;

              // The search itself failed — keep it kind and offer a retry that
              // re-runs the current query.
              if (state.errorMessage != null) {
                return ListView(
                  children: [
                    NutritionInlineError(
                      title: 'Search didn’t go through',
                      detail: state.errorMessage,
                      onRetry: () => context.read<FoodSearchBloc>().add(
                        FoodQueryChanged(query),
                      ),
                    ),
                  ],
                );
              }

              // Nothing anywhere — no query, no favorites, no recents. Invite
              // the search with a soft glyph and a hint at the richer ways in.
              if (mergedResults.isEmpty &&
                  favorites.isEmpty &&
                  latest.isEmpty &&
                  suggested.isEmpty) {
                if (!hasQuery) {
                  return _SearchEmptyHint(theme: theme);
                }
                return _NoMatchesRow(
                  query: query,
                  onAddCustom: widget.onAddCustom,
                );
              }
              return ListView(
                children: [
                  // The backend demoted to a past-TTL cache (provider timed out
                  // or errored). Surface the saved results plainly with a
                  // one-tap refresh that re-runs the current query.
                  if (state.isStale) ...[
                    _StaleResultsBanner(
                      ageLabel: state.staleAgeDisplay(),
                      onRefresh: () => context.read<FoodSearchBloc>().add(
                        FoodQueryChanged(query),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                  // Query typed, nothing matched: call out the miss inline with
                  // a way to add the food by hand (favorites/recents are hidden
                  // during an active query, so this is the only thing shown).
                  if (hasQuery && mergedResults.isEmpty) ...[
                    _NoMatchesRow(
                      query: query,
                      onAddCustom: widget.onAddCustom,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                  // Favorites + the quick-pick strip + the picks list are the
                  // empty-state suggestions: show them only when there is no
                  // active query. Once the user is typing they want matches, not
                  // an unfiltered list of past foods (e.g. searching "avocado"
                  // must not surface recent bananas).
                  //
                  // Recent: a horizontal quick-pick strip of the plain recents
                  // when the vertical picks list below is carrying the time-of-
                  // day suggestions; on a thin-history landing (no picks) it
                  // falls back to the legacy merged strip (suggestions first,
                  // each with a sparkle, then recents, deduped by the backend-
                  // compatible food key). One tap re-logs; no vertical cost.
                  if (!hasQuery && quickPicks.isNotEmpty) ...[
                    const _SectionHeader(title: 'Recent'),
                    const SizedBox(height: AppSpacing.x1),
                    FoodQuickStrip(
                      picks: quickPicks,
                      onPick: widget.onAddLatest,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                  // Time-of-day picks: a MacroFactor-style vertical list that
                  // fills the landing below the Recent strip. The header is
                  // meal/time-aware (e.g. "Afternoon picks", "Lunch picks"),
                  // derived from the current hour to match how the suggestions
                  // are bucketed. Each row carries the food's glyph, name, a
                  // "N Cal · P · F · C" macro line + the last-used serving, and a
                  // one-tap + add. When there are no picks yet we show a tasteful
                  // prompt instead of a blank gap — but only once the user has
                  // SOME meal history (a recent; suggestions imply recents too);
                  // a truly empty landing keeps the existing search hint above and
                  // adds nothing here. This whole section is gated on real
                  // recents/suggestions, NOT favorites: a flow that reuses this
                  // view only for favorites (the recipe IngredientPickerSheet,
                  // which passes latest:[] + no suggested) never loads meal
                  // suggestions or logs meals, so it must not surface the
                  // "[time] picks" header or the "log a few meals" prompt above
                  // its favorites.
                  if (!hasQuery) ...[
                    if (timeOfDayPicks.isNotEmpty) ...[
                      _SectionHeader(title: timeOfDayPicksHeader(DateTime.now())),
                      const SizedBox(height: AppSpacing.x1),
                      ...timeOfDayPicks.map(
                        (entry) => _PickRow(
                          entry: entry,
                          onAdd: () => widget.onAddLatest(entry),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x2),
                    ] else if (latest.isNotEmpty) ...[
                      _SectionHeader(title: timeOfDayPicksHeader(DateTime.now())),
                      const SizedBox(height: AppSpacing.x1),
                      const _PicksEmptyPrompt(),
                      const SizedBox(height: AppSpacing.x2),
                    ],
                  ],
                  if (!hasQuery && favorites.isNotEmpty) ...[
                    const _SectionHeader(title: 'Favorites'),
                    const SizedBox(height: AppSpacing.x1),
                    ...favorites.map(
                      (food) => _FoodResultRow(
                        food: food,
                        isFavorite: widget.isFavorite(food),
                        expanded: _expandedFoodId == food.id,
                        onTap: () => _toggleExpanded(food.id),
                        onToggleFavorite: () => widget.onToggleFavorite(food),
                        onAdd: (grams) {
                          widget.onAddFood(food, grams);
                          setState(() => _expandedFoodId = null);
                        },
                        onCancel: () => setState(() => _expandedFoodId = null),
                        onAddDefault: widget.onAddDefault == null
                            ? null
                            : () => widget.onAddDefault!(food),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                  if (mergedResults.isNotEmpty) ...[
                    if (hasQuery) const _SectionHeader(title: 'Results'),
                    if (hasQuery) const SizedBox(height: AppSpacing.x1),
                    ...mergedResults.map(
                      (food) => _FoodResultRow(
                        food: food,
                        isFavorite: widget.isFavorite(food),
                        expanded: _expandedFoodId == food.id,
                        onTap: () => _toggleExpanded(food.id),
                        onToggleFavorite: () => widget.onToggleFavorite(food),
                        onAdd: (grams) {
                          widget.onAddFood(food, grams);
                          setState(() => _expandedFoodId = null);
                        },
                        onCancel: () => setState(() => _expandedFoodId = null),
                        onAddDefault: widget.onAddDefault == null
                            ? null
                            : () => widget.onAddDefault!(food),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Merges the time-of-day [suggested] picks and the [recents] into ONE combined
/// quick-pick list: suggestions FIRST (the most time-relevant picks, each marked
/// with a subtle sparkle), then the recents. Deduped by [backendCompatibleKey]
/// so a food that's both a suggestion and a recent appears once — kept as the
/// suggestion (first). Mirrors how the strip merges them so re-logging a staple
/// is a single tap with no separate "Suggested for now" section above Recent.
List<FoodQuickPick> _mergeQuickPicks(
  List<FoodLogEntry> suggested,
  List<FoodLogEntry> recents,
) {
  final picks = <FoodQuickPick>[];
  final seen = <String>{};
  void add(FoodLogEntry entry, {required bool isSuggestion}) {
    final key = backendCompatibleKey(entry);
    // Empty-keyed entries can't be deduped reliably; keep them rather than
    // collapse unrelated foods together.
    if (key.isNotEmpty && !seen.add(key)) return;
    picks.add(FoodQuickPick(entry, isSuggestion: isSuggestion));
  }

  for (final entry in suggested) {
    add(entry, isSuggestion: true);
  }
  for (final entry in recents) {
    add(entry, isSuggestion: false);
  }
  return picks;
}

/// Shown when there's truly nothing to display yet (no query, no favorites, no
/// recents). A soft glyph and a line that invites the search and points at the
/// richer ways in — scan a barcode, snap a photo.
class _SearchEmptyHint extends StatelessWidget {
  const _SearchEmptyHint({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.10),
              ),
              child: HustlIcon(
                asset: 'assets/icons/empty_nutrition.svg',
                size: 30,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Search any food',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Type a name, scan a barcode, or snap a photo to add it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet row that names the missed query and offers a manual add so a food we
/// don't have in the database is never a dead end.
class _NoMatchesRow extends StatelessWidget {
  const _NoMatchesRow({required this.query, this.onAddCustom});

  final String query;
  final VoidCallback? onAddCustom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No foods match “$query”',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onAddCustom != null) ...[
          const SizedBox(height: AppSpacing.x1),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddCustom,
              icon: const Icon(Icons.edit_note_outlined, size: 20),
              label: const Text('Add custom food'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Soft banner shown when results came from a saved (past-TTL) cache because
/// the live food provider timed out or errored. Tapping re-runs the search.
class _StaleResultsBanner extends StatelessWidget {
  const _StaleResultsBanner({required this.ageLabel, required this.onRefresh});

  final String ageLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.secondaryContainer,
      borderRadius: AppRadius.controlRadius,
      child: InkWell(
        onTap: onRefresh,
        borderRadius: AppRadius.controlRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x1 + 4,
          ),
          child: Row(
            children: [
              Icon(Icons.history, size: 20, color: colors.onSecondaryContainer),
              const SizedBox(width: AppSpacing.x1 + 4),
              Expanded(
                child: Text(
                  'Showing saved results — $ageLabel — tap to refresh',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              Icon(Icons.refresh, size: 20, color: colors.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodResultRow extends StatelessWidget {
  const _FoodResultRow({
    required this.food,
    required this.isFavorite,
    required this.expanded,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onAdd,
    required this.onCancel,
    this.onAddDefault,
  });

  final Food food;
  final bool isFavorite;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final ValueChanged<double> onAdd;
  final VoidCallback onCancel;

  /// Quick multi-add: commits the food at its default serving without expanding
  /// the inline stepper. Null hides the '+' affordance.
  final VoidCallback? onAddDefault;

  @override
  Widget build(BuildContext context) {
    final subtitle = food.hasMacros
        ? formatMacros(
            protein: food.proteinPer100g ?? 0,
            fat: food.fatPer100g ?? 0,
            carbs: food.carbsPer100g ?? 0,
            calories: food.caloriesPer100g,
          )
        : 'Macros incomplete';
    // ODbL attribution: a per-result data-source line. OFF rows credit Open
    // Food Facts and FDC rows credit USDA; custom rows show nothing.
    final sourceLabel = foodSourceBadgeLabel(food.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _EmojiBubble(name: food.name),
          title: Text(food.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subtitle),
              // Trust signal: a quiet "Recent" provenance hint for a food
              // resurfaced from the user's own log history, a "Verified" chip for
              // lab/government-grade rows, or a muted "Macros incomplete" hint.
              // Community/custom/null tiers show nothing so the list stays
              // uncluttered. Recent wins the slot — it's the most useful signal
              // for a food you've logged before ("you've had this").
              if (food.trustTier == 'recent') ...[
                const SizedBox(height: 4),
                _TrustBadge.recent(loggedCount: food.loggedCount),
              ] else if (food.trustTier == 'verified') ...[
                const SizedBox(height: 4),
                const _TrustBadge.verified(),
              ] else if (food.macrosIncomplete) ...[
                const SizedBox(height: 4),
                const _TrustBadge.macrosIncomplete(),
              ],
              if (sourceLabel != null) ...[
                const SizedBox(height: 4),
                _SourceBadge(label: sourceLabel),
              ],
            ],
          ),
          onTap: onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Favorites are a pure backend reference, so in real mode only
              // foods with a canonical backend UUID can be saved — on-device
              // generic foods carry an asset id the backend can't resolve, so we
              // hide the star rather than enqueue a favorite that never
              // reconciles. Demo mode uses its own non-UUID ids and supports
              // favorites locally, so keep the star there.
              if (kDemoMode || isBackendFoodId(food.id))
                IconButton(
                  onPressed: onToggleFavorite,
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
                ),
              // Quick multi-add: drop the food onto the plate at its default
              // serving in one tap, keeping the search open for the next pick.
              // Shown alongside the stepper toggle so power users can batch.
              // Primary action: one-tap add at the default serving (keeps the
              // search open for the next pick). Filled so it reads as the
              // default, with adjust-serving demoted to a quiet secondary.
              if (onAddDefault != null)
                IconButton.filled(
                  onPressed: onAddDefault,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                onPressed: onTap,
                icon: Icon(expanded ? Icons.expand_less : Icons.tune),
                tooltip: expanded ? 'Collapse' : 'Adjust serving',
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: expanded
              ? AddFoodPortionStepper(
                  food: food,
                  onAdd: onAdd,
                  onCancel: onCancel,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Maps a [Food.source] to its ODbL/public-domain attribution label, or null
/// for sources that need no per-result credit (custom and unknown sources).
String? foodSourceBadgeLabel(String source) {
  switch (source.trim().toLowerCase()) {
    case 'off':
      return 'Source: Open Food Facts';
    case 'fdc':
      return 'Source: USDA';
    default:
      return null;
  }
}

/// A small, neutral data-source badge shown under a search result name. Styled
/// from theme tokens (neutral secondary container + caption voice) so it reads
/// as quiet attribution rather than a status pill.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: AppRadius.controlRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _TrustBadgeVariant { verified, macrosIncomplete, recent }

/// A compact trust signal under a search result name. Three quiet variants:
/// - [verified]: an emerald/success-tinted "Verified" chip for lab- or
///   government-grade rows (FDC Foundation/SR/Survey, reviewed customs).
/// - [macrosIncomplete]: a muted "Macros incomplete" hint (no fill) for rows
///   missing a core macro.
/// - [recent]: a muted "Recent" provenance hint (optionally "Recent · logged
///   Nx") for a food resurfaced from the user's own log history. Styled like the
///   fill-free [macrosIncomplete] variant so it reads as a quiet provenance hint,
///   not a loud status pill.
/// All read from theme tokens only so they track light/dark and the palette.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge.verified()
    : _variant = _TrustBadgeVariant.verified,
      _label = 'Verified',
      _loggedCount = null;

  const _TrustBadge.macrosIncomplete()
    : _variant = _TrustBadgeVariant.macrosIncomplete,
      _label = 'Macros incomplete',
      _loggedCount = null;

  const _TrustBadge.recent({int? loggedCount})
    : _variant = _TrustBadgeVariant.recent,
      _label = 'Recent',
      _loggedCount = loggedCount;

  final _TrustBadgeVariant _variant;
  final String _label;
  final int? _loggedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_variant == _TrustBadgeVariant.recent) {
      // Muted, fill-free provenance hint. "Recent" alone, or "Recent · logged
      // Nx" when we know the count — quiet, like the macros-incomplete hint.
      final count = _loggedCount ?? 0;
      final text = count > 1 ? 'Recent · logged ${count}x' : 'Recent';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 12, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (_variant == _TrustBadgeVariant.macrosIncomplete) {
      // Muted, fill-free hint — quieter than the source attribution badge.
      return Text(
        _label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    // Emerald/success tint. Prefer the brand emerald token; it doubles as the
    // theme's tertiary (success) hue, so the chip stays on-palette in both modes.
    final accent = AppColors.accentEmeraldGreen;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x1,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: AppRadius.controlRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            _label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiBubble extends StatelessWidget {
  const _EmojiBubble({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 18,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: FoodGlyph(name: name, size: 24),
    );
  }
}

/// The meal/time-of-day label for the vertical picks section header, derived
/// from [now]'s local hour to match the diary's meal-slot bucketing
/// (Breakfast / Lunch / Dinner buckets) and the suggestion ranker's
/// time-of-day grouping. A part-of-day word reads better than a literal clock,
/// so: 5–11 → "Morning picks", 11–17 → "Afternoon picks", 17–22 → "Evening
/// picks", else → "Late-night picks". Sentence case, the "picks" suffix lower.
String timeOfDayPicksHeader(DateTime now) {
  final hour = now.toLocal().hour;
  final String part;
  if (hour >= 5 && hour < 11) {
    part = 'Morning';
  } else if (hour >= 11 && hour < 17) {
    part = 'Afternoon';
  } else if (hour >= 17 && hour < 22) {
    part = 'Evening';
  } else {
    part = 'Late-night';
  }
  return '$part picks';
}

/// A rich vertical row for a time-of-day pick: the food's glyph, its name
/// ([TextTheme.bodyLarge]), a quiet secondary line of the last-used serving +
/// the "N Cal · P · F · C" macro breakdown, and a trailing filled + that re-logs
/// the food at that same serving in one tap (the same action as the Recent
/// strip's quick-pick). Mirrors a diary tile's anatomy so the picks read as
/// "your usual around now", ready to log without searching.
class _PickRow extends StatelessWidget {
  const _PickRow({required this.entry, required this.onAdd});

  final FoodLogEntry entry;
  final VoidCallback onAdd;

  /// "1 breast (166 g)"-style serving text: the saved [FoodLogEntry.portionLabel]
  /// when present, else the gram weight. Null when neither is known, so the row
  /// shows just the macro line rather than an empty "·".
  String? _servingLabel() {
    final portion = entry.portionLabel?.trim();
    if (portion != null && portion.isNotEmpty) return portion;
    if (entry.servingGrams > 0) return '${entry.servingGrams.toStringAsFixed(0)} g';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = entry.foodName ?? entry.food?.name ?? 'Food';
    // MacroFactor-style: "204 Cal · 33P · 7F · 0C" with the serving leading.
    final macros = formatMacros(
      protein: entry.proteinGrams,
      fat: entry.fatGrams,
      carbs: entry.carbsGrams,
      calories: entry.calories,
    );
    final serving = _servingLabel();
    final secondLine = serving == null ? macros : '$serving · $macros';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 / 2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.surfaceContainerHighest,
            child: FoodGlyph(name: name, size: 26),
          ),
          const SizedBox(width: AppSpacing.x1 + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  secondLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          IconButton.filled(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            tooltip: 'Add',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Shown under the picks header when there are no time-of-day suggestions yet
/// (a new user whose history is too thin for the backend's min-count guards).
/// A quiet line that explains the empty slot will fill itself, rather than
/// leaving a blank gap.
class _PicksEmptyPrompt extends StatelessWidget {
  const _PicksEmptyPrompt();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 20,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.x1 + 4),
          Expanded(
            child: Text(
              'Log a few meals and we’ll suggest your usual here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
