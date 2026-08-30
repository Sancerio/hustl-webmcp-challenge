import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/utils/number_format_util.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../../domain/utils/warm_up_planner.dart';

/// Normalises typed weight input for the target field. Comma-decimal keyboards
/// (and pasted strings like "52,5") emit a `,` as the decimal separator; a plain
/// `allow([0-9.])` filter would *drop* the comma and silently concatenate the
/// digits ("52,5" -> "525"), letting Apply ramp a ladder off a 525 kg target.
/// Instead we rewrite `,` to `.` and keep at most one separator, so "52,5"
/// parses as 52.5. The edit is rejected (old value kept) rather than mangled
/// when it would introduce a second separator, so digits never concatenate
/// across a dropped one.
class _WeightInputFormatter extends TextInputFormatter {
  const _WeightInputFormatter();

  static final RegExp _allowed = RegExp(r'[0-9.]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final buffer = StringBuffer();
    var sawSeparator = false;
    for (final rune in text.runes) {
      var char = String.fromCharCode(rune);
      // Treat a comma as a decimal point so comma-decimal locales work.
      if (char == ',') char = '.';
      if (!_allowed.hasMatch(char)) {
        // Disallowed character (e.g. a stray letter) — reject the whole edit
        // rather than splice digits together across the removed character.
        return oldValue;
      }
      if (char == '.') {
        // A second separator would change the meaning of the number; reject the
        // edit and keep the prior value instead of dropping the separator and
        // gluing the fractional digits onto the integer part.
        if (sawSeparator) return oldValue;
        sawSeparator = true;
      }
      buffer.write(char);
    }
    final normalised = buffer.toString();
    if (normalised == text) return newValue;
    // We rewrote at least one character (a comma -> dot); re-place the cursor at
    // the end of the normalised text so editing stays predictable.
    return TextEditingValue(
      text: normalised,
      selection: TextSelection.collapsed(offset: normalised.length),
    );
  }
}

/// Result of the warm-up planner sheet. [apply] carries the selected
/// suggestions to materialise as warm-up sets; null means the lifter dismissed
/// without changing anything (Skip / Cancel / backdrop).
class WarmUpPlannerResult {
  const WarmUpPlannerResult(this.suggestions);

  /// The suggestions the lifter chose to apply. An EMPTY list is meaningful:
  /// it removes existing warm-ups (the "Remove warm-ups" path).
  final List<WarmUpSuggestion> suggestions;
}

/// Bottom sheet that ramps warm-up sets from a [seed] target — and lets the
/// lifter override that target live. The %-ladder recomputes from the editable
/// "Target weight" field on every change, so there is no "log a working set
/// first" gate: a typed number is enough.
///
/// Returns a [WarmUpPlannerResult] when the lifter applies or removes warm-ups,
/// or null when they dismiss (Skip / Cancel).
Future<WarmUpPlannerResult?> showWarmUpPlannerSheet(
  BuildContext context, {
  required WarmUpSeed? seed,
  required bool isAssisted,
  required bool hasExistingWarmUps,
}) {
  return showModalBottomSheet<WarmUpPlannerResult>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _WarmUpPlannerSheet(
        seed: seed,
        isAssisted: isAssisted,
        hasExistingWarmUps: hasExistingWarmUps,
      );
    },
  );
}

class _WarmUpPlannerSheet extends StatefulWidget {
  const _WarmUpPlannerSheet({
    required this.seed,
    required this.isAssisted,
    required this.hasExistingWarmUps,
  });

  final WarmUpSeed? seed;
  final bool isAssisted;
  final bool hasExistingWarmUps;

  @override
  State<_WarmUpPlannerSheet> createState() => _WarmUpPlannerSheetState();
}

class _WarmUpPlannerSheetState extends State<_WarmUpPlannerSheet> {
  late final TextEditingController _targetController;
  late int _reps;
  List<WarmUpSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    _reps = seed?.reps ?? 5;
    final seedWeight = seed?.displayWeight;
    // Seed with a PARSE-STABLE canonical number, NOT
    // NumberFormatUtil.formatWeight: that is locale-aware and can emit
    // thousands/decimal separators (e.g. "52,5" or "1,000") that
    // double.tryParse in _recompute rejects — which would silently yield no
    // suggestions and a disabled Apply until the user retyped the value. The
    // field only accepts `[0-9.]` anyway, so a plain `.`-decimal string with
    // trailing zeros trimmed is both clean to read and round-trips through
    // double.tryParse.
    _targetController = TextEditingController(
      text: seedWeight != null ? _canonicalNumber(seedWeight) : '',
    );
    _recompute();
  }

  /// A plain, parse-stable rendering of [value]: up to two decimals (matching
  /// the precision logged weights carry), no thousands separator, trailing
  /// zeros trimmed. Always uses `.` as the decimal point so [double.tryParse]
  /// accepts it regardless of locale.
  static String _canonicalNumber(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return text;
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  /// Parse the typed target (always a positive magnitude) and rebuild the
  /// ladder. Preserves prior selection state by index so toggles survive edits.
  void _recompute() {
    final typed = double.tryParse(_targetController.text.trim());
    final target = typed ?? 0;
    final next = buildWarmUpSuggestions(
      targetWeight: target,
      reps: _reps,
      isAssisted: widget.isAssisted,
    );
    // Carry selection state across recomputes so editing the target doesn't
    // silently re-check rows the lifter unchecked.
    for (var i = 0; i < next.length && i < _suggestions.length; i++) {
      next[i].selected = _suggestions[i].selected;
    }
    _suggestions = next;
  }

  String? _seedLabel() {
    final seed = widget.seed;
    if (seed == null) return null;
    final weight = NumberFormatUtil.formatWeight(seed.displayWeight);
    final suffix = widget.isAssisted ? ' (assisted)' : '';
    switch (seed.source) {
      case WarmUpSeedSource.currentSet:
        return 'Ramping from your first working set — $weight kg × ${seed.reps}$suffix';
      case WarmUpSeedSource.pr:
        return 'Ramping from PR $weight kg × ${seed.reps}$suffix';
      case WarmUpSeedSource.previousSession:
        return 'Ramping from your last workout — $weight kg × ${seed.reps}$suffix';
      case WarmUpSeedSource.typed:
        return 'Ramping from $weight kg × ${seed.reps}$suffix';
    }
  }

  void _toggle(WarmUpSuggestion option) {
    Haptics.selection();
    setState(() => option.selected = !option.selected);
  }

  void _clearSelection() {
    Haptics.selection();
    setState(() {
      for (final option in _suggestions) {
        option.selected = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final selectedCount = _suggestions.where((s) => s.selected).length;
    final hasSuggestions = _suggestions.isNotEmpty;
    final seedLabel = _seedLabel();
    final canApply = hasSuggestions || widget.hasExistingWarmUps;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.x3,
          right: AppSpacing.x3,
          top: AppSpacing.x1 + 2,
          bottom: mediaQuery.viewInsets.bottom + AppSpacing.x2,
        ),
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxContentWidth: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      borderRadius: AppRadius.pillRadius,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                // --- Header: title + seed origin, tight rhythm ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: AppRadius.controlRadius,
                      ),
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x1 + 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warm-up sets',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            seedLabel ?? 'Type a target weight to ramp from.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2 + 4),
                // Editable target. Suggestions recompute live as it changes, so
                // the lifter can ramp from any number — no logged set required.
                TextField(
                  key: const Key('warmupTargetField'),
                  controller: _targetController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [_WeightInputFormatter()],
                  style: AppTextStyles.metric(theme.textTheme.bodyLarge!),
                  decoration: InputDecoration(
                    labelText: 'Target weight',
                    suffixText: 'kg',
                    prefixIcon: Icon(
                      Icons.fitness_center_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadius.controlRadius,
                    ),
                  ),
                  onChanged: (_) => setState(_recompute),
                ),
                if (widget.hasExistingWarmUps)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.x1),
                    child: Row(
                      children: [
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Your existing warm-up sets will be replaced.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.x2 + 4),
                if (hasSuggestions)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: mediaQuery.size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.x1),
                      itemBuilder: (context, index) {
                        final option = _suggestions[index];
                        return _WarmUpRungTile(
                          suggestion: option,
                          step: index,
                          totalSteps: _suggestions.length,
                          onTap: () => _toggle(option),
                        );
                      },
                    ),
                  )
                else
                  // Graceful fallback: no data and no typed target. Quiet hint,
                  // never a scary snackbar.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x2,
                      vertical: AppSpacing.x2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: AppRadius.cardRadius,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tips_and_updates_rounded,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.x1 + 4),
                        Expanded(
                          child: Text(
                            'Enter a target weight to generate warm-up sets.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.x3),
                // --- Primary CTA ---
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('warmupApply'),
                    // Disabled until there is something to apply OR remove.
                    onPressed: canApply
                        ? () {
                            Haptics.confirm();
                            context.pop(
                              WarmUpPlannerResult(
                                _suggestions.where((s) => s.selected).toList(),
                              ),
                            );
                          }
                        : null,
                    child: Text(
                      selectedCount == 0
                          ? 'Remove warm-ups'
                          : 'Apply $selectedCount set${selectedCount == 1 ? '' : 's'}',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                // --- Secondary actions, laid out in one clean row ---
                Row(
                  children: [
                    if (hasSuggestions && selectedCount != 0)
                      Expanded(
                        child: TextButton(
                          onPressed: _clearSelection,
                          child: const Text('Clear selection'),
                        ),
                      ),
                    if (widget.hasExistingWarmUps)
                      Expanded(
                        child: TextButton(
                          onPressed: () => context.pop(
                            const WarmUpPlannerResult(<WarmUpSuggestion>[]),
                          ),
                          child: const Text('Remove existing'),
                        ),
                      ),
                    Expanded(
                      child: TextButton(
                        key: const Key('warmupSkip'),
                        onPressed: () => context.pop(),
                        child: Text(hasSuggestions ? 'Cancel' : 'Skip'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single polished, full-row-tappable warm-up rung. The weight is the hero
/// (large, tabular), the %-of-target and reps ride alongside as quiet data,
/// and a subtle "ramp" bar visualises the 40 → 60 → 75% progression. The
/// selected state is a crisp accent fill + check, not a stock checkbox.
class _WarmUpRungTile extends StatelessWidget {
  const _WarmUpRungTile({
    required this.suggestion,
    required this.step,
    required this.totalSteps,
    required this.onTap,
  });

  final WarmUpSuggestion suggestion;
  final int step;
  final int totalSteps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = suggestion.selected;
    final percentLabel = (suggestion.percentage * 100).round();
    final weightLabel = NumberFormatUtil.formatWeight(suggestion.weight.abs());
    // Visual ramp cue: each rung shows a little more "fill" than the last so the
    // 40 → 60 → 75% progression reads at a glance. Falls back gracefully for a
    // single rung.
    final rampFraction = totalSteps <= 1 ? 1.0 : (step + 1) / totalSteps;

    final selectedColor = colors.primary;

    return Semantics(
      button: true,
      selected: selected,
      label:
          'Warm-up $weightLabel kilograms, $percentLabel percent, ${suggestion.reps} reps',
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.enterCurve,
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.10)
              : colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: selected
                ? selectedColor.withValues(alpha: 0.55)
                : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.cardRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x1 + 4,
              ),
              child: Row(
                children: [
                  // Weight (hero) + ramp cue.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              weightLabel,
                              style: AppTextStyles.metric(
                                theme.textTheme.titleMedium!,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 3),
                            Text('kg', style: theme.textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _RampBar(
                          fraction: rampFraction,
                          color: selected
                              ? selectedColor
                              : colors.onSurfaceVariant.withValues(alpha: 0.5),
                          trackColor: colors.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  // %-of-target + reps as quiet, aligned data.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$percentLabel%',
                        style: AppTextStyles.metric(theme.textTheme.labelLarge!)
                            .copyWith(
                              color: selected
                                  ? selectedColor
                                  : colors.onSurface,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${suggestion.reps} reps',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  // Crisp selected state: accent fill + check, not a checkbox.
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.enterCurve,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected ? selectedColor : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? selectedColor : colors.outline,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: colors.onPrimary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slim horizontal bar whose fill grows with the ramp [fraction], giving each
/// warm-up rung a subtle "more load than the last" cue.
class _RampBar extends StatelessWidget {
  const _RampBar({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.pillRadius,
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Container(color: trackColor),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: AnimatedContainer(
                duration: AppMotion.medium,
                curve: AppMotion.enterCurve,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
