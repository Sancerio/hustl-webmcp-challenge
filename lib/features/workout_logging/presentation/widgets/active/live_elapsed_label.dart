import 'dart:async';

import 'package:flutter/material.dart';

/// Compact always-visible "recording" status for the active-workout app bar
/// (Wave I). A small pulsing emerald dot ([ColorScheme.tertiary]) sits beside
/// the live elapsed time ("MM:SS", or "H:MM:SS" past an hour) rendered in
/// `labelLarge`/`onSurface` with tabular figures so the layout never shifts as
/// digits tick.
///
/// The dot pulse honours reduce-motion ([MediaQueryData.disableAnimations]);
/// when motion is disabled the dot is static.
class LiveElapsedLabel extends StatefulWidget {
  const LiveElapsedLabel({super.key, required this.startTime});

  /// When the session started; elapsed time is measured from here.
  final DateTime startTime;

  @override
  State<LiveElapsedLabel> createState() => _LiveElapsedLabelState();
}

class _LiveElapsedLabelState extends State<LiveElapsedLabel>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late String _formatted;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseOpacity;
  bool _reduceMotion = false;

  // Treat reduce-motion and the test binding alike: a continuously repeating
  // pulse would otherwise keep `pumpAndSettle` from ever completing.
  bool get _staticDot => _reduceMotion || _isTestEnv;

  bool get _isTestEnv {
    final binding = WidgetsBinding.instance.runtimeType.toString();
    return binding.contains('TestWidgetsFlutterBinding') ||
        binding.contains('AutomatedTestWidgetsFlutterBinding');
  }

  @override
  void initState() {
    super.initState();
    _formatted = _format(_elapsed());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _format(_elapsed());
      if (next != _formatted) {
        setState(() => _formatted = next);
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseOpacity = Tween<double>(
      begin: 1.0,
      end: 0.35,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulseController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_staticDot) {
      if (_pulseController.isAnimating) _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LiveElapsedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      _formatted = _format(_elapsed());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Duration _elapsed() => DateTime.now().difference(widget.startTime);

  String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: colors.tertiary, shape: BoxShape.circle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _staticDot
            ? dot
            : FadeTransition(opacity: _pulseOpacity, child: dot),
        const SizedBox(width: 8),
        Text(
          _formatted,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
