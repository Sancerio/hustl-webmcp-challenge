import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/core/services/preferences_service.dart';
import 'package:hustl_app/core/widgets/hustl_snack.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

import '../../domain/repositories/nutrition_targets_repository.dart';
import '../nutrition_view_cache.dart';
import '../utils/weight_unit.dart';

enum _WeightUnit { kg, lb }

class WeightEntrySheet extends StatefulWidget {
  const WeightEntrySheet({
    super.key,
    required this.date,
    this.onLogged,
    this.initialUnit,
  });

  final DateTime date;
  final VoidCallback? onLogged;

  /// Already-resolved kg/lb preference from the caller. Pass this whenever
  /// the caller has one (see weight_log_card.dart, diary_screen.dart) so
  /// this sheet never has to race an async prefs read while its field is
  /// editable. Null only for callers not yet migrated to pass it
  /// (weight_trend_screen.dart, out of scope for this plan) — the sheet
  /// falls back to resolving it internally and disables the field until
  /// that resolves.
  final WeightUnit? initialUnit;

  @override
  State<WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends State<WeightEntrySheet> {
  static const double _kgPerLb = 0.45359237;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSaving = false;
  _WeightUnit _unit = _WeightUnit.kg;
  bool _unitReady = false; // gates the field's `enabled` until unit is known
  double? _latestWeightKg;
  double? _dayWeightKg;
  String? _daySource;

  @override
  void initState() {
    super.initState();
    if (widget.initialUnit != null) {
      // Already resolved by the caller before this sheet became
      // interactive — no async read here, so there is no race to guard.
      _unit = widget.initialUnit!.isLb ? _WeightUnit.lb : _WeightUnit.kg;
      _unitReady = true;
    } else {
      // No caller-supplied unit. Resolve it here, but the field stays
      // disabled (see `enabled: _unitReady` on the TextField below) for the
      // brief window until it resolves, so a race can't misinterpret typed
      // input as the wrong unit.
      _resolveUnit();
    }
    _seedFromCache();
    // Never block on the network: if nothing prefilled the field, focus it now
    // so the user can type immediately instead of waiting for the fetch.
    if (_controller.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
    _revalidate();
  }

  /// Fallback path when no caller passes [widget.initialUnit] (only
  /// weight_trend_screen.dart today, out of scope for this plan). The field
  /// is disabled (`enabled: _unitReady`) until this resolves, so there is no
  /// clobber race even though this read is async.
  Future<void> _resolveUnit() async {
    final raw = await PreferencesService().getWeightUnit();
    if (!mounted) return;
    final next = raw == 'lb' ? _WeightUnit.lb : _WeightUnit.kg;
    if (next == _unit) {
      setState(() => _unitReady = true);
      return;
    }
    final currentKg = _tryParseNonNegativeInKg(_controller);
    setState(() {
      _unit = next;
      _unitReady = true;
    });
    if (currentKg != null) _setDisplayedWeightKg(currentKg);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Pulls today's and the latest weigh-in out of a weight-trend payload.
  ({double? forDay, String? forDaySource, double? latest}) _readTrend(
    Map<dynamic, dynamic> trend,
  ) {
    double? latest;
    double? forDay;
    String? forDaySource;
    final scale = (trend['scale'] as List?) ?? const [];
    final dayKey = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    ).toIso8601String().substring(0, 10);
    for (final point in scale) {
      if (point is! Map) continue;
      final weight = (point['weightKg'] as num?)?.toDouble();
      if (weight == null || weight <= 0) continue;
      latest = weight;
      if (point['date']?.toString() == dayKey) {
        forDay = weight;
        forDaySource = point['source']?.toString();
      }
    }
    return (forDay: forDay, forDaySource: forDaySource, latest: latest);
  }

  /// Applies parsed weights to state, seeding the field only if the user hasn't
  /// started typing — so a late network result never clobbers their input.
  void _applyWeights(
    ({double? forDay, String? forDaySource, double? latest}) w,
  ) {
    _latestWeightKg = w.latest;
    _dayWeightKg = w.forDay;
    _daySource = w.forDaySource;
    final initialKg = w.forDay ?? w.latest;
    if (initialKg != null && initialKg > 0 && _controller.text.trim().isEmpty) {
      _setDisplayedWeightKg(initialKg);
    }
  }

  /// Instant, synchronous prefill from the weight-trend cache (today only — the
  /// default 30-day range the trend screen stores). A miss just falls through to
  /// [_revalidate]; either way the input is usable immediately.
  void _seedFromCache() {
    final now = DateTime.now();
    final isToday =
        widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
    if (!isToday) return;
    final trend = NutritionViewCache.instance.get<Map<String, dynamic>>(
      'weight:30',
    );
    if (trend != null) _applyWeights(_readTrend(trend));
  }

  Future<void> _revalidate() async {
    Map<String, dynamic>? trend;
    try {
      final repo = GetIt.instance<NutritionTargetsRepository>();
      final end = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
      );
      final start = end.subtract(const Duration(days: 30));
      trend = await repo.getWeightTrend(start, end);
    } catch (_) {
      // Best-effort prefill only; the field is already usable.
    }
    if (!mounted || trend == null) return;
    setState(() => _applyWeights(_readTrend(trend!)));
  }

  double _toKg(double value) =>
      _unit == _WeightUnit.kg ? value : value * _kgPerLb;

  double _fromKg(double kg) => _unit == _WeightUnit.kg ? kg : kg / _kgPerLb;

  String get _unitLabel => _unit == _WeightUnit.kg ? 'kg' : 'lb';

  double? _tryParseNonNegativeInKg(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null || value < 0) return null;
    return _toKg(value);
  }

  void _setDisplayedWeightKg(double kg) {
    final display = _fromKg(kg);
    _controller.text = display.toStringAsFixed(1);
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _adjustKg(double deltaKg) {
    final currentKg = _tryParseNonNegativeInKg(_controller);
    final nextKg = ((currentKg ?? 0) + deltaKg).clamp(0.0, 500.0);
    _setDisplayedWeightKg(nextKg);
    HapticFeedback.selectionClick();
  }

  void _setUnit(_WeightUnit next) {
    if (next == _unit) return;
    final currentKg = _tryParseNonNegativeInKg(_controller);
    setState(() => _unit = next);
    if (currentKg != null) {
      _setDisplayedWeightKg(currentKg);
    }
    HapticFeedback.selectionClick();
  }

  String _formatDelta(double deltaKg) {
    final value = _fromKg(deltaKg.abs());
    if (value % 1 == 0) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  void _useLatest() {
    final latest = _latestWeightKg;
    if (latest == null) return;
    _setDisplayedWeightKg(latest);
    HapticFeedback.selectionClick();
  }

  Future<void> _submit() async {
    final weightKg = _tryParseNonNegativeInKg(_controller);
    final router = GoRouter.of(context);

    if (weightKg == null || weightKg <= 0) {
      HustlSnack.show(
        context,
        'Enter a valid weight ($_unitLabel).',
        variant: HustlSnackVariant.warning,
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await GetIt.instance<NutritionTargetsRepository>().addWeightSample(
        widget.date,
        weightKg,
      );
      widget.onLogged?.call();
      if (!mounted) return;
      // Show via the captured messenger context so the success toast survives
      // the sheet being popped on the next line.
      HustlSnack.show(
        context,
        'Logged weigh-in.',
        variant: HustlSnackVariant.success,
        actionLabel: 'View',
        onAction: () => router.push('/nutrition/weight'),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      HustlSnack.show(
        context,
        message.trim().isEmpty
            ? 'Couldn’t log weight. Please try again.'
            : message,
        variant: HustlSnackVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daySource = (_daySource ?? '').toLowerCase();
    final isEditing = _dayWeightKg != null && daySource == 'self';
    final isOverride =
        _dayWeightKg != null && daySource.isNotEmpty && daySource != 'self';
    final canUseLatest = _latestWeightKg != null;

    final displayInUnit = () {
      final kg = _tryParseNonNegativeInKg(_controller);
      if (kg == null) return null;
      return _fromKg(kg);
    }();
    final displayText = displayInUnit == null
        ? '—'
        : displayInUnit.toStringAsFixed(1);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ResponsiveCenter(
        maxContentWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  isOverride ? 'Override weigh-in' : 'Log weigh-in',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isEditing || isOverride) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      isOverride ? 'Synced' : 'Edit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.98,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  '$displayText $_unitLabel',
                  key: ValueKey('$displayText|$_unitLabel'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap below to type, or use quick adjust.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<_WeightUnit>(
                    segments: const [
                      ButtonSegment(value: _WeightUnit.kg, label: Text('kg')),
                      ButtonSegment(value: _WeightUnit.lb, label: Text('lb')),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (_isSaving || !_unitReady)
                        ? null
                        : (s) => _setUnit(s.first),
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                if (canUseLatest) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: (_isSaving || !_unitReady) ? null : _useLatest,
                    child: const Text('Use last'),
                  ),
                ],
              ],
            ),
            if (isOverride) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'This day already has a synced weigh-in. Saving creates a manual override.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'For best trend: weigh in in the morning, after the bathroom.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !_isSaving && _unitReady,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(labelText: 'Weight ($_unitLabel)'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text('-${_formatDelta(0.5)}'),
                  onPressed: (_isSaving || !_unitReady)
                      ? null
                      : () => _adjustKg(-0.5),
                ),
                ActionChip(
                  label: Text('-${_formatDelta(0.1)}'),
                  onPressed: (_isSaving || !_unitReady)
                      ? null
                      : () => _adjustKg(-0.1),
                ),
                ActionChip(
                  label: Text('+${_formatDelta(0.1)}'),
                  onPressed: (_isSaving || !_unitReady)
                      ? null
                      : () => _adjustKg(0.1),
                ),
                ActionChip(
                  label: Text('+${_formatDelta(0.5)}'),
                  onPressed: (_isSaving || !_unitReady)
                      ? null
                      : () => _adjustKg(0.5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_isSaving || !_unitReady) ? null : _submit,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _isSaving
                      ? const Row(
                          key: ValueKey('saving'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Saving…'),
                          ],
                        )
                      : Text(
                          key: const ValueKey('save'),
                          isOverride ? 'Save override' : 'Save',
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
