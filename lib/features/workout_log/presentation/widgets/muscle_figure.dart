import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/theme/app_radius.dart';
import '../../domain/models/muscle_group.dart';
import 'body_heat_map.dart';

/// A read-only muscle figure rendered from the shared [MuscleSvgComposer]
/// engine. Primary muscles read confident blue, untrained regions stay neutral.
/// Shows a calm placeholder while the SVG template loads and an icon tile if it
/// fails — never a black void.
///
/// Shared by the exercise-detail hero and the template-list thumbnails so both
/// highlight the same regions with the same tint.
class MuscleFigure extends StatefulWidget {
  const MuscleFigure({
    super.key,
    required this.primary,
    required this.height,
    this.intensity = defaultIntensity,
  });

  final Set<MuscleGroup> primary;
  final double height;

  /// Highlight strength for primary muscles. The composer maps low intensity to
  /// blue, so a calm value keeps primaries clearly blue (not the heat scale).
  final double intensity;

  /// A single calm blue accent, not the volume heat scale.
  static const double defaultIntensity = 0.45;

  @override
  State<MuscleFigure> createState() => _MuscleFigureState();
}

class _MuscleFigureState extends State<MuscleFigure> {
  static String? _templateCache;
  static Future<String>? _pendingTemplate;

  String? _template;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _template = _templateCache;
    if (_template == null) _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    _pendingTemplate ??= rootBundle.loadString(
      'assets/images/muscle-body-detailed.svg',
    );
    try {
      final raw = await _pendingTemplate!;
      _templateCache = raw;
      if (!mounted) return;
      setState(() {
        _template = raw;
        _loadFailed = false;
      });
    } catch (error) {
      debugPrint('Failed to load muscle SVG for figure: $error');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_template == null) {
      if (_loadFailed) {
        return Center(
          child: Icon(
            Icons.fitness_center,
            size: widget.height < 64 ? 20 : 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      }
      // Calm static placeholder (not a shimmering skeleton) while the SVG
      // template loads — it renders synchronously once cached, and a static box
      // keeps the frame pipeline quiet so the scene can settle.
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.cardRadius,
        ),
        child: SizedBox(height: widget.height, width: double.infinity),
      );
    }

    final intensities = <MuscleGroup, double>{
      for (final g in widget.primary) g: widget.intensity,
    };

    final composer = MuscleSvgComposer(_template!);
    return RepaintBoundary(
      child: SvgPicture.string(
        composer.build(intensities: intensities, theme: theme),
        fit: BoxFit.contain,
      ),
    );
  }
}
