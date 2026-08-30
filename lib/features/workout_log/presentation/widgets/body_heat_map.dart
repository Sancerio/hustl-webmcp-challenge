import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';
import 'package:hustl_app/features/nutrition_tracker/presentation/widgets/segmented_pill_selector.dart';

import '../../domain/services/body_score_service.dart';

/// Shared thresholds (in % of weekly goal) so the heat-map legend, the
/// silhouette tint, and the focus summary all agree on what counts as a lot vs
/// a little. At or below [_kNeedsMoreAtOrBelow]% a muscle reads as "needs more";
/// at or above [_kTrainedMostAtOrAbove]% it reads as "trained most"; in between
/// it is "on target". The tint saturates at [_kHeatMapSaturatesAt]× the goal —
/// mapping a threshold to a bar fraction is `pctOfGoal / 100 / saturatesAt`.
const double _kNeedsMoreAtOrBelow = 60;
const double _kTrainedMostAtOrAbove = 110;
const double _kHeatMapSaturatesAt = 1.5;

class BodyHeatMap extends StatefulWidget {
  const BodyHeatMap({
    super.key,
    required this.metricsByStrategy,
    required this.strategies,
    required this.weeklyTargetsByStrategy,
    this.initialStrategyId,
    Map<MuscleGroup, Map<String, double>>? breakdown,
    this.lookback = const Duration(days: 28),
    this.loading = false,
    this.templateOverride,
  }) : assert(strategies.length > 0, 'strategies must not be empty'),
       breakdown = breakdown ?? const {};

  final Map<String, Map<MuscleGroup, BodyRegionMetrics>> metricsByStrategy;
  final List<BodyScoreStrategy> strategies;
  final Map<String, Map<MuscleGroup, double>> weeklyTargetsByStrategy;
  final String? initialStrategyId;
  final Map<MuscleGroup, Map<String, double>> breakdown;
  final Duration lookback;
  final bool loading;
  final String? templateOverride;

  @override
  State<BodyHeatMap> createState() => _BodyHeatMapState();
}

class _BodyHeatMapState extends State<BodyHeatMap> {
  String? _svgTemplate;
  bool _loadFailed = false;
  late Map<MuscleGroup, double> _volumes;
  late String _selectedStrategyId;
  late Map<MuscleGroup, double> _weeklyTargets;

  static String? _templateCache;
  static Future<String>? _pendingTemplate;

  @override
  void initState() {
    super.initState();
    _selectedStrategyId =
        widget.initialStrategyId != null &&
            widget.metricsByStrategy.containsKey(widget.initialStrategyId)
        ? widget.initialStrategyId!
        : widget.strategies.first.id;
    _volumes = _volumesForStrategy(_selectedStrategyId);
    _weeklyTargets = _targetsForStrategy(_selectedStrategyId);
    _svgTemplate = widget.templateOverride ?? _templateCache;
    if (_svgTemplate == null) {
      _loadSvgTemplate();
    }
  }

  @override
  void didUpdateWidget(covariant BodyHeatMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSelectedId =
        widget.metricsByStrategy.containsKey(_selectedStrategyId)
        ? _selectedStrategyId
        : widget.strategies.first.id;
    final nextVolumes = _volumesForStrategy(nextSelectedId);
    final nextTargets = _targetsForStrategy(nextSelectedId);
    if (nextSelectedId != _selectedStrategyId ||
        !mapEquals(_volumes, nextVolumes) ||
        !mapEquals(_weeklyTargets, nextTargets)) {
      setState(() {
        _selectedStrategyId = nextSelectedId;
        _volumes = nextVolumes;
        _weeklyTargets = nextTargets;
      });
    }
    if (oldWidget.templateOverride != widget.templateOverride &&
        widget.templateOverride != null) {
      setState(() {
        _svgTemplate = widget.templateOverride;
      });
    }
  }

  Map<MuscleGroup, double> _volumesForStrategy(String strategyId) {
    final metrics = widget.metricsByStrategy[strategyId];
    if (metrics == null) {
      return {for (final group in MuscleGroup.values) group: 0.0};
    }
    return {
      for (final group in MuscleGroup.values)
        group: metrics[group]?.volume ?? 0.0,
    };
  }

  Map<MuscleGroup, double> _targetsForStrategy(String strategyId) {
    final targets = widget.weeklyTargetsByStrategy[strategyId];
    final base = targets == null || targets.isEmpty
        ? defaultWeeklyTargetsByMuscleGroup
        : targets;
    return {
      for (final group in MuscleGroup.values)
        group: base[group] ?? (defaultWeeklyTargetsByMuscleGroup[group] ?? 0.0),
    };
  }

  BodyScoreStrategy get _selectedStrategy {
    return widget.strategies.firstWhere(
      (strategy) => strategy.id == _selectedStrategyId,
      orElse: () => widget.strategies.first,
    );
  }

  Map<MuscleGroup, BodyRegionMetrics> get _selectedMetrics {
    return widget.metricsByStrategy[_selectedStrategyId] ??
        const <MuscleGroup, BodyRegionMetrics>{};
  }

  Future<void> _loadSvgTemplate() async {
    _pendingTemplate ??= rootBundle.loadString(
      'assets/images/muscle-body-detailed.svg',
    );
    try {
      final raw = await _pendingTemplate!;
      _templateCache = raw;
      if (!mounted) return;
      setState(() {
        _svgTemplate = raw;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load muscle SVG: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Map<MuscleGroup, double> get _normalizedIntensities {
    final output = <MuscleGroup, double>{};
    for (final group in MuscleGroup.values) {
      final value = _volumes[group] ?? 0.0;
      final target =
          _weeklyTargets[group] ??
          (defaultWeeklyTargetsByMuscleGroup[group] ?? 0.0);
      final highAnchor = target > 0 ? target * _kHeatMapSaturatesAt : 0.0;
      final normalized = highAnchor > 0
          ? (value / highAnchor).clamp(0.0, 1.0)
          : 0.0;
      output[group] = normalized;
    }
    return output;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intensities = _buildMuscleIntensities();
    final displayRegionIntensities = _buildDisplayRegionIntensities();
    final selectedMetrics = _selectedMetrics;
    final strategy = _selectedStrategy;
    final summary = _buildIntensitySummary(
      intensities,
      selectedMetrics,
      strategy,
    );
    final composer = _svgTemplate == null
        ? null
        : MuscleSvgComposer(_svgTemplate!);

    // Wave I: grouped surface card (no outline) so the heat map reads as a
    // premium module that sits above the canvas, not a bordered enterprise box.
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeatMapHeader(
              lookback: widget.lookback,
              strategies: widget.strategies,
              selectedStrategyId: _selectedStrategyId,
              onStrategyChanged: (value) {
                if (value == _selectedStrategyId) return;
                setState(() {
                  _selectedStrategyId = value;
                  _volumes = _volumesForStrategy(value);
                  _weeklyTargets = _targetsForStrategy(value);
                });
              },
            ),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: summary,
              child: ExcludeSemantics(
                child: Text(
                  summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _IntensityLegend(),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.of(context).size.width;
                final desiredHeight = width / 1.15;
                final clampedHeight = desiredHeight.clamp(180.0, 260.0);
                return SizedBox(
                  height: clampedHeight.toDouble(),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _buildSilhouette(
                      composer: composer,
                      theme: theme,
                      intensities: intensities,
                      displayRegionIntensities: displayRegionIntensities,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSilhouette({
    required MuscleSvgComposer? composer,
    required ThemeData theme,
    required Map<MuscleGroup, double> intensities,
    required Map<DisplayRegion, double> displayRegionIntensities,
  }) {
    final key = ValueKey('heatmap-${composer != null}');

    if (composer == null) {
      if (!_loadFailed) {
        _loadSvgTemplate();
      }
      // Calm, map-shaped placeholder (skeleton-over-spinner): a gently pulsing
      // box sized to the silhouette, rather than a lone centred spinner.
      return AppSkeleton(
        key: key,
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(12),
      );
    }

    return SvgPicture.string(
      composer.build(
        intensities: intensities,
        displayRegionIntensities: displayRegionIntensities,
        theme: theme,
      ),
      key: key,
      fit: BoxFit.contain,
    );
  }

  String _buildIntensitySummary(
    Map<MuscleGroup, double> intensities,
    Map<MuscleGroup, BodyRegionMetrics> metrics,
    BodyScoreStrategy strategy,
  ) {
    final windowDays = widget.lookback.inDays;
    final renderableGroups = MuscleSvgComposer.renderableMuscleGroups;
    final hasVolume = metrics.entries
        .where((entry) => entry.key != MuscleGroup.other)
        .where((entry) => renderableGroups.contains(entry.key))
        .any((entry) => entry.value.volume > 0);
    final hasHipFlexorVolume =
        (metrics[MuscleGroup.hipFlexors]?.volume ?? 0) > 0;
    if (!hasVolume && !hasHipFlexorVolume) {
      return 'No training recorded in the last $windowDays days.';
    }

    final regionTotals = <DisplayRegion, double>{
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final regionTargets = <DisplayRegion, double>{
      for (final region in DisplayRegion.values) region: 0.0,
    };
    for (final group in MuscleGroup.values) {
      final target =
          _weeklyTargets[group] ??
          (defaultWeeklyTargetsByMuscleGroup[group] ?? 0.0);
      if (target <= 0) continue;
      regionTargets[group.displayRegion] =
          (regionTargets[group.displayRegion] ?? 0) + target;
      regionTotals[group.displayRegion] =
          (regionTotals[group.displayRegion] ?? 0) +
          (metrics[group]?.volume ?? 0.0);
    }

    final nonOtherEntries = DisplayRegion.values
        .where((region) => region != DisplayRegion.other)
        .map((region) {
          final target = regionTargets[region] ?? 0.0;
          final value = regionTotals[region] ?? 0.0;
          final score = target > 0 ? (value / target) * 100 : 0.0;
          return MapEntry(region, score);
        })
        .toList(growable: false);
    final hasNonOtherStimulus = DisplayRegion.values
        .where((r) => r != DisplayRegion.other)
        .any((region) => (regionTotals[region] ?? 0) > 0);
    final otherStimulus = regionTotals[DisplayRegion.other] ?? 0.0;
    if (!hasNonOtherStimulus && otherStimulus > 0) {
      return 'Last $windowDays-day rolling '
          '${strategy.label.toLowerCase()} focus: ${DisplayRegion.other.label}.';
    }

    final highEntries =
        nonOtherEntries
            .where((entry) => entry.value >= _kTrainedMostAtOrAbove)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final lowEntries =
        nonOtherEntries
            .where((entry) => entry.value <= _kNeedsMoreAtOrBelow)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    String? formatLimited(List<MapEntry<DisplayRegion, double>> entries) {
      if (entries.isEmpty) return null;
      const limit = 2;
      final shown = entries.take(limit).map((e) => e.key.label).toList();
      final remaining = entries.length - shown.length;
      if (remaining > 0) {
        shown.add('+$remaining more');
      }
      return shown.join(', ');
    }

    final focusParts = <String>[];
    final highLabel = formatLimited(highEntries);
    final lowLabel = formatLimited(lowEntries);
    if (highLabel != null) {
      focusParts.add('trained most: $highLabel');
    }
    if (lowLabel != null) {
      focusParts.add('needs more: $lowLabel');
    }
    if (focusParts.isEmpty) {
      return 'Last $windowDays days — balanced across all muscle groups.';
    }
    return 'Last $windowDays days — ${focusParts.join('; ')}.';
  }

  Map<MuscleGroup, double> _buildMuscleIntensities() {
    final output = Map<MuscleGroup, double>.from(_normalizedIntensities);

    // Hip flexors have no dedicated SVG region; map their hard sets onto quads.
    // Combine raw values/targets first (not already-normalized intensities).
    final quadsVolume = _volumes[MuscleGroup.quads] ?? 0.0;
    final hipFlexorsVolume = _volumes[MuscleGroup.hipFlexors] ?? 0.0;
    final quadsTarget =
        _weeklyTargets[MuscleGroup.quads] ??
        (defaultWeeklyTargetsByMuscleGroup[MuscleGroup.quads] ?? 0.0);
    final hipFlexorsTarget =
        _weeklyTargets[MuscleGroup.hipFlexors] ??
        (defaultWeeklyTargetsByMuscleGroup[MuscleGroup.hipFlexors] ?? 0.0);

    final combinedTarget = quadsTarget + hipFlexorsTarget;
    final combinedHighAnchor = combinedTarget > 0 ? combinedTarget * 1.5 : 0.0;
    final combinedIntensity = combinedHighAnchor > 0
        ? ((quadsVolume + hipFlexorsVolume) / combinedHighAnchor).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    output[MuscleGroup.quads] = combinedIntensity;
    return output;
  }

  Map<DisplayRegion, double> _buildDisplayRegionIntensities() {
    final totals = <DisplayRegion, double>{
      for (final region in DisplayRegion.values) region: 0.0,
    };
    final targets = <DisplayRegion, double>{
      for (final region in DisplayRegion.values) region: 0.0,
    };

    for (final group in MuscleGroup.values) {
      final target =
          _weeklyTargets[group] ??
          (defaultWeeklyTargetsByMuscleGroup[group] ?? 0.0);
      if (target <= 0) continue;
      totals[group.displayRegion] =
          (totals[group.displayRegion] ?? 0) + (_volumes[group] ?? 0.0);
      targets[group.displayRegion] =
          (targets[group.displayRegion] ?? 0) + target;
    }

    return {
      for (final region in DisplayRegion.values)
        region: () {
          final target = targets[region] ?? 0.0;
          final highAnchor = target > 0 ? target * _kHeatMapSaturatesAt : 0.0;
          if (highAnchor <= 0) return 0.0;
          final value = totals[region] ?? 0.0;
          return (value / highAnchor).clamp(0.0, 1.0);
        }(),
    };
  }
}

class _HeatMapHeader extends StatelessWidget {
  const _HeatMapHeader({
    required this.lookback,
    required this.strategies,
    required this.selectedStrategyId,
    required this.onStrategyChanged,
  });

  final Duration lookback;
  final List<BodyScoreStrategy> strategies;
  final String selectedStrategyId;
  final ValueChanged<String> onStrategyChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = lookback.inDays;
    final selected = strategies.firstWhere(
      (strategy) => strategy.id == selectedStrategyId,
      orElse: () => strategies.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Body heat map',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Always the most recent $days days',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message:
                  'Shows your last $days days of ${selected.label.toLowerCase()}, ending today and updating daily. This map ignores the date range you pick above.',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Last $days days',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (strategies.length > 1)
          SegmentedPillSelector<String>(
            options: strategies.map((s) => s.id).toList(),
            selected: selectedStrategyId,
            labels: {
              for (final strategy in strategies) strategy.id: strategy.label,
            },
            onSelect: onStrategyChanged,
          )
        else
          Text(
            selected.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          selected.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This map always shows your last $days days; the muscle list below follows the period you picked.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _IntensityLegend extends StatelessWidget {
  const _IntensityLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MuscleSvgComposer.gradientSwatches(theme);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    const double barHeight = 8;
    const double tickHeight = 12;
    const double tickWidth = 1;

    // Tick positions map the shared thresholds into the bar's intensity space
    // (intensity = %goal / (100 * saturatesAt)), so the legend's three zones
    // line up with the focus summary's "needs more" / "on target" / "trained
    // most" classification and the silhouette tint — the colours, the body
    // figure, and the sentence all agree on what counts as a lot vs a little.
    const lowFrac = _kNeedsMoreAtOrBelow / 100 / _kHeatMapSaturatesAt;
    const highFrac = _kTrainedMostAtOrAbove / 100 / _kHeatMapSaturatesAt;

    Widget zone(String label, double fraction) => Expanded(
      flex: (fraction * 1000).round(),
      child: Text(
        label,
        style: labelStyle,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: tickHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final tickColor = theme.colorScheme.onSurfaceVariant.withValues(
                alpha: 0.6,
              );
              final bar = Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: width,
                  height: barHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: colors,
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              );
              return Stack(
                children: [
                  bar,
                  for (final fraction in [lowFrac, highFrac])
                    Positioned(
                      left: width * fraction - (tickWidth / 2),
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: tickWidth,
                          height: tickHeight,
                          color: tickColor,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            zone('Needs more', lowFrac),
            zone('On target', highFrac - lowFrac),
            zone('Trained most', 1 - highFrac),
          ],
        ),
      ],
    );
  }
}

class MuscleSvgComposer {
  MuscleSvgComposer(this.template);

  final String template;

  static const Map<String, DisplayRegion> _displayRegionLookup = {
    // Legacy data-region keys (templateOverride support)
    'front-chest': DisplayRegion.chest,
    'back-back': DisplayRegion.back,
    'front-shoulders': DisplayRegion.shoulders,
    'back-shoulders': DisplayRegion.shoulders,
    'front-arms': DisplayRegion.arms,
    'back-arms': DisplayRegion.arms,
    'front-core': DisplayRegion.core,
    'front-legs': DisplayRegion.legs,
    'back-legs': DisplayRegion.legs,

    // Generic display-region keys
    'chest': DisplayRegion.chest,
    'back': DisplayRegion.back,
    'shoulders': DisplayRegion.shoulders,
    'arms': DisplayRegion.arms,
    'core': DisplayRegion.core,
    'legs': DisplayRegion.legs,
    'other': DisplayRegion.other,
  };

  static const Map<String, MuscleGroup> _regionLookup = {
    // Front view - Chest
    'upper_pecs': MuscleGroup.upperPecs,
    'middle_pecs': MuscleGroup.middlePecs,
    'lower_pecs': MuscleGroup.lowerPecs,

    // Front view - Shoulders
    'front_delts': MuscleGroup.frontDelts,
    'side_delts': MuscleGroup.sideDelts,

    // Front view - Arms
    'biceps': MuscleGroup.biceps,
    'forearms': MuscleGroup.forearms,

    // Front view - Core
    'upper_abs': MuscleGroup.upperAbs,
    'lower_abs': MuscleGroup.lowerAbs,
    'obliques': MuscleGroup.obliques,

    // Front view - Legs
    'quads': MuscleGroup.quads,
    'hip_adductors': MuscleGroup.hipAdductors,
    'hip_adductor': MuscleGroup.hipAdductors,
    'calves': MuscleGroup.calves,

    // Back view - Shoulders & Back
    'rear_delts': MuscleGroup.rearDelts,
    'upper_traps': MuscleGroup.upperTraps,
    'lower_traps': MuscleGroup.lowerTraps,
    'rhomboids': MuscleGroup.rhomboids,
    'lats': MuscleGroup.lats,
    'lower_back': MuscleGroup.lowerBack,

    // Back view - Arms
    'triceps': MuscleGroup.triceps,

    // Back view - Legs
    'glutes': MuscleGroup.glutes,
    'hamstrings': MuscleGroup.hamstrings,
    'hip_abductors': MuscleGroup.hipAbductors,
    'hip_abductor': MuscleGroup.hipAbductors,

    // Special
    'neck': MuscleGroup.neck,
  };

  static Set<MuscleGroup> get renderableMuscleGroups =>
      Set<MuscleGroup>.unmodifiable(_regionLookup.values);

  String build({
    required Map<MuscleGroup, double> intensities,
    Map<DisplayRegion, double> displayRegionIntensities = const {},
    required ThemeData theme,
  }) {
    final doc = XmlDocument.parse(template);
    _stripUnsupportedElements(doc);
    final neutral = _neutralColor(theme);

    // Pass 1: recolor the non-muscle BASE body (head, hands, feet, facial
    // features, silhouette outline) so it reads as a soft, theme-appropriate
    // grey body instead of solid-black blobs / black voids. The SVG defines
    // head/hand/feet paths with a default (black) fill and #000000 strokes,
    // which the muscle pass below never touches because they are not mapped
    // regions. We resolve each paintable element's fill/stroke and, when it is
    // black (explicit or SVG-default), swap it to the silhouette tone. Mapped
    // muscle/display regions are skipped here and handled by the muscle pass.
    _applyBaseSilhouette(doc, theme);

    // Pass 2: recolor mapped muscle / display regions with the intensity
    // highlight (or the untrained neutral). This runs last so trained-muscle
    // data always wins over the base silhouette underneath it.
    for (final element in doc.descendants.whereType<XmlElement>()) {
      final regionKey =
          element.getAttribute('data-region') ?? element.getAttribute('id');
      if (regionKey == null) continue;
      final muscleGroup = _regionLookup[regionKey];
      final displayRegion = muscleGroup == null
          ? _displayRegionLookup[regionKey]
          : null;
      if (muscleGroup == null && displayRegion == null) continue;

      final intensity =
          (muscleGroup != null
              ? intensities[muscleGroup]
              : displayRegionIntensities[displayRegion]) ??
          0.0;
      final Color color = intensity > 0
          ? _highlightColor(intensity, theme)
          : neutral;
      _applyColorToSubtree(element, color);
    }

    return doc.toXmlString();
  }

  /// Recolors the non-muscle base body to a quiet, theme-appropriate
  /// silhouette. Any paintable element that is not part of a mapped
  /// muscle/display region and whose resolved fill or stroke is black (or the
  /// SVG-default black) is repainted with [_silhouetteFill] / [_silhouetteStroke].
  static void _applyBaseSilhouette(XmlDocument doc, ThemeData theme) {
    final Color fill = _silhouetteFill(theme);
    final Color stroke = _silhouetteStroke(theme);

    // Collect every paintable element that belongs to a mapped region subtree
    // so the base pass leaves the muscle data untouched.
    final Set<XmlElement> regionOwned = <XmlElement>{};
    for (final element in doc.descendants.whereType<XmlElement>()) {
      final regionKey =
          element.getAttribute('data-region') ?? element.getAttribute('id');
      if (regionKey == null) continue;
      if (!_regionLookup.containsKey(regionKey) &&
          !_displayRegionLookup.containsKey(regionKey)) {
        continue;
      }
      regionOwned.add(element);
      regionOwned.addAll(element.findAllElements('*'));
    }

    for (final element in doc.descendants.whereType<XmlElement>()) {
      if (!_isPaintableElement(element)) continue;
      if (regionOwned.contains(element)) continue;

      final String? resolvedFill = element.getAttribute('fill');
      final String? resolvedStroke = element.getAttribute('stroke');

      // Fill: SVG defaults an unset fill to black, so treat null as black too.
      // Keep explicit fill="none" as a non-painted fill (e.g. outline-only
      // border paths) but still recolor its stroke below so it stays visible.
      if (_isBlackPaint(resolvedFill) || resolvedFill == null) {
        element.setAttribute('fill', _toHex(fill));
        element.setAttribute(
          'fill-opacity',
          fill.a.clamp(0.0, 1.0).toStringAsFixed(3),
        );
      }

      // Stroke: only repaint strokes that are explicitly black; the unset
      // default stroke is "none" (invisible) and should stay that way.
      if (_isBlackPaint(resolvedStroke)) {
        element.setAttribute('stroke', _toHex(stroke));
        element.setAttribute(
          'stroke-opacity',
          stroke.a.clamp(0.0, 1.0).toStringAsFixed(3),
        );
      }
    }
  }

  /// Returns true when [value] resolves to black (#000000 / #000 / black).
  static bool _isBlackPaint(String? value) {
    if (value == null) return false;
    final normalized = value.trim().toLowerCase();
    return normalized == '#000000' ||
        normalized == '#000' ||
        normalized == 'black' ||
        normalized == 'rgb(0,0,0)';
  }

  /// Quiet, theme-appropriate fill for the base body silhouette (head, hands,
  /// feet, facial features). Blends [onSurfaceVariant] toward the surface so it
  /// reads as a soft grey body in both light and dark themes — visible, but
  /// clearly subordinate to the trained-muscle highlights.
  static Color _silhouetteFill(ThemeData theme) {
    final bool light = theme.brightness == Brightness.light;
    final Color base = theme.colorScheme.onSurfaceVariant;
    final Color blended =
        Color.lerp(base, theme.colorScheme.surface, light ? 0.62 : 0.55) ??
        base;
    return blended.withValues(alpha: light ? 0.55 : 0.6);
  }

  /// Slightly firmer tone than [_silhouetteFill] so outlines/facial features
  /// keep a touch of definition without reading as hard black lines.
  static Color _silhouetteStroke(ThemeData theme) {
    final bool light = theme.brightness == Brightness.light;
    final Color base = theme.colorScheme.onSurfaceVariant;
    final Color blended =
        Color.lerp(base, theme.colorScheme.surface, light ? 0.4 : 0.32) ?? base;
    return blended.withValues(alpha: light ? 0.7 : 0.72);
  }

  static void _stripUnsupportedElements(XmlDocument doc) {
    _inlineCssClassStyles(doc);
    const unsupportedTags = {'path-effect', 'namedview', 'metadata', 'style'};
    for (final tag in unsupportedTags) {
      final elements = doc.findAllElements(tag, namespace: '*').toList();
      for (final element in elements) {
        element.parent?.children.remove(element);
      }
    }
  }

  static void _inlineCssClassStyles(XmlDocument doc) {
    final Map<String, Map<String, String>> rulesByClass = {};
    final styleElements = doc.findAllElements('style', namespace: '*').toList();
    if (styleElements.isEmpty) return;

    for (final style in styleElements) {
      final css = style.innerText;
      if (css.trim().isEmpty) continue;
      final ruleMatches = RegExp(
        r'\.([A-Za-z0-9_-]+)\s*\{([^}]*)\}',
        multiLine: true,
      ).allMatches(css);
      for (final match in ruleMatches) {
        final className = match.group(1);
        final body = match.group(2);
        if (className == null || body == null) continue;
        final declarations = <String, String>{};
        for (final part in body.split(';')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final idx = trimmed.indexOf(':');
          if (idx <= 0) continue;
          final key = trimmed.substring(0, idx).trim();
          final value = trimmed.substring(idx + 1).trim();
          if (key.isEmpty || value.isEmpty) continue;
          declarations[key] = value;
        }
        if (declarations.isEmpty) continue;
        rulesByClass.update(
          className,
          (existing) => {...existing, ...declarations},
          ifAbsent: () => declarations,
        );
      }
    }

    if (rulesByClass.isEmpty) return;

    for (final element in doc.descendants.whereType<XmlElement>()) {
      final classAttr = element.getAttribute('class');
      if (classAttr == null || classAttr.trim().isEmpty) continue;
      final classNames = classAttr
          .split(RegExp(r'\s+'))
          .where((c) => c.isNotEmpty);
      for (final className in classNames) {
        final rules = rulesByClass[className];
        if (rules == null) continue;
        for (final entry in rules.entries) {
          final attrName = switch (entry.key) {
            'stroke-width' => 'stroke-width',
            'stroke-miterlimit' => 'stroke-miterlimit',
            'stroke-linejoin' => 'stroke-linejoin',
            'stroke' => 'stroke',
            'fill' => 'fill',
            'display' => 'display',
            _ => null,
          };
          if (attrName == null) continue;
          if (element.getAttribute(attrName) != null) continue;
          element.setAttribute(attrName, entry.value);
        }
      }
    }
  }

  static Color _highlightColor(double intensity, ThemeData theme) {
    final palette = _HighlightPalette.fromTheme(theme);
    final clamped = intensity.clamp(0.0, 1.0);
    final eased = math.pow(clamped, 0.8).toDouble();
    final double pivot = math.pow(2 / 3, 0.8).toDouble();

    Color target;
    if (eased <= pivot) {
      final double segmentT = (eased / pivot).clamp(0.0, 1.0);
      target = Color.lerp(palette.low, palette.mid, segmentT) ?? palette.mid;
    } else {
      final double segmentT = (eased - pivot) / (1 - pivot);
      final double limited = segmentT.clamp(0.0, 1.0);
      target = Color.lerp(palette.mid, palette.high, limited) ?? palette.high;
    }

    final alphaProgress = math.pow(clamped, 0.7).toDouble();
    final alpha =
        palette.minAlpha +
        (palette.maxAlpha - palette.minAlpha) * alphaProgress;
    return target.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  static Color _neutralColor(ThemeData theme) {
    final base = theme.colorScheme.onSurface;
    final opacity = theme.brightness == Brightness.light ? 0.12 : 0.2;
    return base.withValues(alpha: opacity);
  }

  static List<Color> gradientSwatches(ThemeData theme) {
    final palette = _HighlightPalette.fromTheme(theme);
    return [
      palette.low.withValues(alpha: 1.0),
      palette.mid.withValues(alpha: 1.0),
      palette.high.withValues(alpha: 1.0),
    ];
  }

  static Color neutralColor(ThemeData theme) => _neutralColor(theme);

  static void _applyColorToSubtree(XmlElement element, Color color) {
    _applyColor(element, color);
    for (final descendant in element.findAllElements('*')) {
      if (!_isPaintableElement(descendant)) continue;
      _applyColor(descendant, color);
    }
  }

  static bool _isPaintableElement(XmlElement element) {
    switch (element.name.local) {
      case 'path':
      case 'polygon':
      case 'rect':
      case 'circle':
      case 'ellipse':
        return true;
    }
    return false;
  }

  static void _applyColor(XmlElement element, Color color) {
    final double opacity = color.a.clamp(0.0, 1.0);
    final Color opaqueColor = color.withValues(alpha: 1.0);
    element.setAttribute('fill', _toHex(opaqueColor));
    element.setAttribute('fill-opacity', opacity.toStringAsFixed(3));
    final hasStroke =
        element.getAttribute('stroke') != null ||
        element.getAttribute('stroke-width') != null;
    if (hasStroke) {
      element.setAttribute('stroke', _toHex(opaqueColor));
      element.setAttribute('stroke-opacity', opacity.toStringAsFixed(3));
    }
  }

  static String _toHex(Color color) {
    final argb = color.toARGB32();
    final r = ((argb >> 16) & 0xFF).toRadixString(16).padLeft(2, '0');
    final g = ((argb >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
    final b = (argb & 0xFF).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }
}

class _HighlightPalette {
  const _HighlightPalette({
    required this.low,
    required this.mid,
    required this.high,
    required this.minAlpha,
    required this.maxAlpha,
  });

  final Color low;
  final Color mid;
  final Color high;
  final double minAlpha;
  final double maxAlpha;

  // Wave I diverging scale built from the restored Hustl palette (no red — red
  // is error-only): under-target reads cool BLUE, at-goal reads EMERALD
  // (success), over-target reads AMBER (the same "over" warning hue as the
  // nutrition over-budget signal). blue -> emerald -> amber.
  static _HighlightPalette fromTheme(ThemeData theme) {
    final bool light = theme.brightness == Brightness.light;
    final Color surface = theme.colorScheme.surface;
    final Color baseBlend = light ? surface : theme.colorScheme.scrim;
    final Color low =
        Color.lerp(
          baseBlend,
          AppColors.accentElectricBlue,
          light ? 0.7 : 0.6,
        ) ??
        AppColors.accentElectricBlue;
    final Color mid =
        Color.lerp(
          baseBlend,
          AppColors.accentEmeraldGreen,
          light ? 0.85 : 0.72,
        ) ??
        AppColors.accentEmeraldGreen;
    final Color high =
        Color.lerp(
          light ? AppColors.brandCloudWhite : theme.colorScheme.scrim,
          AppColors.accentWarningAmber,
          light ? 0.7 : 0.85,
        ) ??
        AppColors.accentWarningAmber;
    final double minAlpha = light ? 0.35 : 0.45;
    final double maxAlpha = light ? 0.98 : 0.92;
    return _HighlightPalette(
      low: low,
      mid: mid,
      high: high,
      minAlpha: minAlpha,
      maxAlpha: maxAlpha,
    );
  }
}
