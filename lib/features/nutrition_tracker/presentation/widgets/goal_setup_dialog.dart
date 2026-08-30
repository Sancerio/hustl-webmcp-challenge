import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/responsive_center.dart';
import '../../domain/models/nutrition_goal_profile.dart';

/// Default weekly rate (kg/week) re-applied when a lose/gain goal is chosen but
/// the rate field is left blank or zero, so we never quietly fall back to a
/// maintain plan the user did not ask for.
const double _kDefaultRatePerWeek = 0.25;

/// DOB picker bounds, kept in lock-step with the backend birth_date write
/// contract (`validateBirthDateForWrite` in hustl_backend/lib/nutrition/age.ts:
/// derived age must be in [MIN_DERIVED_AGE..MAX_DERIVED_AGE] = [13..120]).
/// [_kMinPickerAge] is the youngest selectable age (under-13 floor) and
/// [_kMaxPickerAge] is the oldest, so a saved profile up to 120 stays pickable
/// instead of asserting because its DOB predates `firstDate`.
const int _kMinPickerAge = 13;
const int _kMaxPickerAge = 120;

/// Bottom sheet for the nutrition calorie/macro goal. Seeds EVERY field —
/// goal, weekly rate, date of birth, sex, height, weight, activity — from the last-saved
/// plan + profile so reopening it shows what the user entered before instead of
/// empty placeholders.
///
/// [initialProfile] carries the persisted "about you" inputs (they live on the
/// user profile, not the weekly plan, so they ride alongside it in the targets
/// response). Returns the `{goal, rate, profile?}` map on "Set targets", or null
/// on cancel/dismiss — the calc trigger is unchanged.
Future<Map<String, dynamic>?> showGoalSetupDialog(
  BuildContext context, {
  required String initialGoal,
  double? initialRatePerWeek,
  NutritionGoalProfile? initialProfile,
  bool requireProfile = false,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    builder: (context) {
      return _GoalSetupSheet(
        initialGoal: initialGoal,
        initialRatePerWeek: initialRatePerWeek,
        initialProfile: initialProfile,
        requireProfile: requireProfile,
      );
    },
  );
}

class _GoalSetupSheet extends StatefulWidget {
  const _GoalSetupSheet({
    required this.initialGoal,
    required this.initialRatePerWeek,
    required this.initialProfile,
    required this.requireProfile,
  });

  final String initialGoal;
  final double? initialRatePerWeek;
  final NutritionGoalProfile? initialProfile;
  final bool requireProfile;

  @override
  State<_GoalSetupSheet> createState() => _GoalSetupSheetState();
}

class _GoalSetupSheetState extends State<_GoalSetupSheet> {
  // Sex/activity values the dropdown + chips select from. Seeded from the saved
  // profile so a reopen reflects the last choice, not a hard default.
  static const _sexValues = {'male', 'female', 'other'};
  static const _activityValues = {
    'sedentary',
    'light',
    'moderate',
    'active',
    'very_active',
  };

  late String _selectedGoal;
  late String _selectedActivity;
  late String _selectedSex;

  late final TextEditingController _rateController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;

  // Date of birth is the stored source of truth; age is derived for display. Null
  // until the user picks (we NEVER prefill a fabricated date for legacy age-only
  // profiles). Validation flags a missing pick when requireProfile is set.
  DateTime? _selectedDob;
  // True when the seeded profile carried only a legacy numeric age (no DOB), so
  // we nudge the user to pick a real date without inventing one.
  bool _hasLegacyAgeOnly = false;

  // Inline field error for the weekly rate; surfaced under the field rather than
  // via a post-submit SnackBar so the fix is shown where it happens.
  String? _rateError;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _selectedGoal = widget.initialGoal;
    // Seed sex/activity from the saved profile (validating against the known
    // value sets), falling back to the prior sensible defaults when unset.
    final savedSex = profile?.gender?.toLowerCase();
    _selectedSex = (savedSex != null && _sexValues.contains(savedSex))
        ? savedSex
        : 'male';
    final savedActivity = profile?.activityLevel?.toLowerCase();
    _selectedActivity =
        (savedActivity != null && _activityValues.contains(savedActivity))
        ? savedActivity
        : 'moderate';

    _rateController = TextEditingController(
      text:
          (widget.initialRatePerWeek ??
                  (widget.initialGoal == 'maintain' ? 0 : _kDefaultRatePerWeek))
              .toStringAsFixed(2),
    );
    // Seed the date of birth from the saved profile. Left null (picker empty) when
    // there is no saved DOB — including legacy age-only profiles, where we show a
    // gentle prompt instead of fabricating a date from the old age number.
    _selectedDob = profile?.birthDate;
    _hasLegacyAgeOnly =
        profile?.birthDate == null && profile?.legacyAgeYears != null;
    // Prefill height/weight from the saved profile. Empty when unset so the field
    // still shows its placeholder for a first-time setup.
    _heightController = TextEditingController(
      text: profile?.heightCm?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: profile?.weightKg != null ? _canonicalNumber(profile!.weightKg!) : '',
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// A plain, parse-stable rendering of [value]: up to two decimals, no
  /// thousands separator, trailing zeros trimmed, always `.` as the decimal
  /// point so the seeded text round-trips through [double.tryParse] in any locale.
  static String _canonicalNumber(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return text;
  }

  bool get _isWeightGoal => _selectedGoal != 'maintain';

  String? _validateAndBuildProfile(Map<String, dynamic> out) {
    final dob = _selectedDob;
    final height = int.tryParse(_heightController.text.trim());
    final weight = double.tryParse(
      _weightController.text.trim().replaceAll(',', '.'),
    );

    final hasAny =
        dob != null ||
        _heightController.text.trim().isNotEmpty ||
        _weightController.text.trim().isNotEmpty;

    if (widget.requireProfile) {
      if (dob == null || height == null || weight == null) {
        return 'Add your date of birth, height, and weight so we can '
            'estimate your starting calories.';
      }
    } else if (!hasAny) {
      return null;
    }

    // Emit the date of birth as an ISO 'YYYY-MM-DD' built from LOCAL y/m/d so it
    // round-trips without a timezone shift. Age is derived server-side.
    if (dob != null) out['birthDate'] = _isoDate(dob);
    if (height != null) out['heightCm'] = height;
    if (weight != null) out['weightKg'] = weight;
    out['gender'] = _selectedSex;
    out['activityLevel'] = _selectedActivity;
    return null;
  }

  /// 'YYYY-MM-DD' from a date-only [date]'s LOCAL y/m/d (no UTC conversion, so the
  /// calendar day can never roll back).
  static String _isoDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  /// Clamp [date] into the inclusive [min, max] range so it is always a valid
  /// `initialDate` for [showDatePicker] (which asserts when initialDate is before
  /// firstDate or after lastDate). Returns [min]/[max] when [date] falls outside.
  static DateTime _clampDate(DateTime date, DateTime min, DateTime max) {
    if (date.isBefore(min)) return min;
    if (date.isAfter(max)) return max;
    return date;
  }

  /// Human-friendly DOB label, e.g. '15 Jan 1990'.
  static String _formatDob(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // Mirror the backend birth_date write contract (validateBirthDateForWrite:
    // derived age in [MIN_DERIVED_AGE..MAX_DERIVED_AGE] = [13..120]). The youngest
    // selectable DOB is `today - 13y` (under-13 floor); the oldest is the earliest
    // DOB that still derives age 120 (see `firstDate` below), so saved profiles up
    // to age 120 are still pickable, matching the API's inclusive ceiling.
    // Subtract whole years with clamp-to-last-valid-day so a Feb-29 `now` never
    // overflows to Mar 1 in a non-leap target year — that would shift the under-13
    // floor (`lastDate`) a day later and admit a just-under-13 DOB the backend
    // rejects. Both bounds (and the seed below) stay leap-safe.
    final lastDate = subtractYears(now, _kMinPickerAge);
    // The oldest selectable DOB is the EARLIEST date that still derives age 120,
    // not `today - 120y`. The backend's ceiling is inclusive (derived age <= 120),
    // and any DOB in (today-121y, today-120y] still derives to exactly 120 (you
    // turn 121 only on the next birthday). That earliest date is the day AFTER
    // `today - 121y`, so we add one day to keep the floor in lock-step with the
    // backend instead of excluding a year of valid age-120 DOBs.
    final firstDate = subtractYears(
      now,
      _kMaxPickerAge + 1,
    ).add(const Duration(days: 1));
    // Clamp the seed into [firstDate, lastDate] so showDatePicker can never assert
    // (a null or out-of-range saved DOB falls back to a sensible 25-year-old seed,
    // itself clamped). A DOB before firstDate / after lastDate would otherwise trip
    // the framework's `!initialDate.isBefore(firstDate)` assertion.
    final initial = _clampDate(
      _selectedDob ?? subtractYears(now, 25),
      firstDate,
      lastDate,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select your date of birth',
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked != null) {
      Haptics.selection();
      setState(() {
        _selectedDob = DateTime(picked.year, picked.month, picked.day);
        _hasLegacyAgeOnly = false;
      });
    }
  }

  // Resolve the weekly rate for a lose/gain goal. Returns the parsed rate, or
  // null when the field is blank/zero so the caller can show an inline hint
  // instead of silently producing a maintain plan.
  double? _resolveWeightGoalRate() {
    final parsed = double.tryParse(
      _rateController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  void _onSetTargets() {
    double rate = 0;
    if (_isWeightGoal) {
      final resolved = _resolveWeightGoalRate();
      if (resolved == null) {
        // Blank/zero rate for a weight goal: re-apply the gentle default and
        // show a kind inline hint instead of a silent maintain plan.
        setState(() {
          _rateController.text = _kDefaultRatePerWeek.toStringAsFixed(2);
          _rateError =
              'Pick a weekly rate to see targets. '
              'We added a gentle default to start.';
        });
        return;
      }
      rate = resolved;
    }
    final profile = <String, dynamic>{};
    final error = _validateAndBuildProfile(profile);
    if (error != null) {
      HustlSnack.show(context, error, variant: HustlSnackVariant.warning);
      return;
    }
    Haptics.confirm();
    context.pop({
      'goal': _selectedGoal,
      'rate': rate,
      if (profile.isNotEmpty) 'profile': profile,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            AppSpacing.x1,
            AppSpacing.x3,
            AppSpacing.x2,
          ),
          child: ResponsiveCenter(
            maxContentWidth: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header: icon holder + title/subtitle, tight rhythm ---
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
                        Icons.flag_rounded,
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
                            'Set your goal',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Set a goal and we\'ll calculate your daily '
                            'calorie and macro targets.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2 + 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionLabel('Goal'),
                        const SizedBox(height: AppSpacing.x1),
                        _SegmentedChips(
                          options: const [
                            ('lose', 'Lose'),
                            ('maintain', 'Maintain'),
                            ('gain', 'Gain'),
                          ],
                          selected: _selectedGoal,
                          onSelected: (v) => setState(() {
                            Haptics.selection();
                            _selectedGoal = v;
                            _rateError = null;
                          }),
                        ),
                        if (_isWeightGoal) ...[
                          const SizedBox(height: AppSpacing.x2),
                          TextField(
                            key: const Key('goalRateField'),
                            controller: _rateController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) {
                              if (_rateError != null) {
                                setState(() => _rateError = null);
                              }
                            },
                            style: AppTextStyles.metric(
                              theme.textTheme.bodyLarge!,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Weekly rate',
                              suffixText: 'kg/week',
                              helperText:
                                  'A steady pace is 0.1 to 0.5 kg per week.',
                              errorText: _rateError,
                              border: const OutlineInputBorder(
                                borderRadius: AppRadius.controlRadius,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.x3),
                        const _SectionLabel('About you'),
                        const SizedBox(height: AppSpacing.x1),
                        Row(
                          children: [
                            Expanded(
                              child: _BirthDateField(
                                key: const Key('goalBirthDateField'),
                                value: _selectedDob,
                                hasLegacyAgeOnly: _hasLegacyAgeOnly,
                                onTap: _pickDob,
                                formatDob: _formatDob,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x1 + 4),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: const Key('goalSexField'),
                                initialValue: _selectedSex,
                                borderRadius: AppRadius.controlRadius,
                                decoration: const InputDecoration(
                                  labelText: 'Sex',
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.controlRadius,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'male',
                                    child: Text('Male'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'female',
                                    child: Text('Female'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'other',
                                    child: Text('Other'),
                                  ),
                                ],
                                onChanged: (v) => setState(
                                  () => _selectedSex = v ?? _selectedSex,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x1 + 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('goalHeightField'),
                                controller: _heightController,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.metric(
                                  theme.textTheme.bodyLarge!,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Height',
                                  suffixText: 'cm',
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.controlRadius,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x1 + 4),
                            Expanded(
                              child: TextField(
                                key: const Key('goalWeightField'),
                                controller: _weightController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: AppTextStyles.metric(
                                  theme.textTheme.bodyLarge!,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Weight',
                                  suffixText: 'kg',
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.controlRadius,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        const _SectionLabel('Activity'),
                        const SizedBox(height: AppSpacing.x1),
                        _SegmentedChips(
                          options: const [
                            ('sedentary', 'Sedentary'),
                            ('light', 'Light'),
                            ('moderate', 'Moderate'),
                            ('active', 'Active'),
                            ('very_active', 'Very active'),
                          ],
                          selected: _selectedActivity,
                          onSelected: (v) => setState(() {
                            Haptics.selection();
                            _selectedActivity = v;
                          }),
                        ),
                        if (widget.requireProfile) ...[
                          const SizedBox(height: AppSpacing.x2),
                          const _InfoHint(
                            'We use your date of birth, height, weight and '
                            'activity to estimate your starting calories until '
                            'you have enough logs for us to learn your real '
                            'daily calorie estimate.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                // --- Primary CTA ---
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('goalSetTargets'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: _onSetTargets,
                    child: const Text('Set targets'),
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const Key('goalCancel'),
                    onPressed: () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tap-to-open date-of-birth field styled like the Height/Weight inputs
/// ([InputDecorator] + [OutlineInputBorder]). Shows the formatted DOB or a
/// placeholder, a trailing calendar icon, and the DERIVED age as helper text.
/// For a legacy age-only profile (no saved DOB) it stays empty with a gentle
/// prompt rather than fabricating a date.
class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    super.key,
    required this.value,
    required this.hasLegacyAgeOnly,
    required this.onTap,
    required this.formatDob,
  });

  final DateTime? value;
  final bool hasLegacyAgeOnly;
  final VoidCallback onTap;
  final String Function(DateTime) formatDob;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dob = value;

    final String? helper;
    if (dob != null) {
      helper = 'Age ${ageFromBirthDate(dob, DateTime.now())}';
    } else if (hasLegacyAgeOnly) {
      helper = 'Pick your date of birth to keep targets accurate';
    } else {
      helper = null;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.controlRadius,
      child: InputDecorator(
        isEmpty: dob == null,
        decoration: InputDecoration(
          labelText: 'Date of birth',
          helperText: helper,
          helperMaxLines: 2,
          suffixIcon: Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          border: const OutlineInputBorder(
            borderRadius: AppRadius.controlRadius,
          ),
        ),
        child: Text(
          dob != null ? formatDob(dob) : '',
          style: AppTextStyles.metric(theme.textTheme.bodyLarge!),
        ),
      ),
    );
  }
}

/// Section label in the warm-up-planner voice: 13/w600 onSurfaceVariant.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}

/// A polished single-select chip row: crisp accent fill + check on the selected
/// chip, quiet outlined surface otherwise — matching the warm-up planner tiles
/// rather than stock [ChoiceChip]s.
class _SegmentedChips extends StatelessWidget {
  const _SegmentedChips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String value, String label)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.x1,
      runSpacing: AppSpacing.x1,
      children: options.map((o) {
        final isSelected = selected == o.$1;
        return _SegmentChip(
          label: o.$2,
          selected: isSelected,
          onTap: () => onSelected(o.$1),
        );
      }).toList(),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = colors.primary;

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.enterCurve,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: AppRadius.pillRadius,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.pillRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x1 + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 16, color: accent),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: null,
                      color: selected ? accent : colors.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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

/// A quiet, supportive hint block (icon + text) on a tinted surface — the same
/// graceful-fallback voice the warm-up planner uses, never a scary snackbar.
class _InfoHint extends StatelessWidget {
  const _InfoHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1 + 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.tips_and_updates_rounded,
            size: 20,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.x1 + 4),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
