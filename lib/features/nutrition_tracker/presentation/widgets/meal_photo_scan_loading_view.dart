import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class MealPhotoScanLoadingView extends StatefulWidget {
  const MealPhotoScanLoadingView({
    super.key,
    required this.imageBytes,
    required this.hintText,
    required this.onCancel,
    this.onLogManuallyInstead,
    this.isTakingLong = false,
    this.showItemsSkeleton = true,
  });

  /// The captured photo shown behind the scanning shimmer. Null on the
  /// describe-a-meal (text-only) path, where the header renders without a photo.
  final Uint8List? imageBytes;
  final String hintText;
  final VoidCallback onCancel;
  final VoidCallback? onLogManuallyInstead;
  final bool isTakingLong;
  final bool showItemsSkeleton;

  @override
  State<MealPhotoScanLoadingView> createState() =>
      _MealPhotoScanLoadingViewState();
}

class _MealPhotoScanLoadingViewState extends State<MealPhotoScanLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.outlineVariant.withValues(alpha: 0.22);
    final highlight = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.42 : 0.75,
    );
    final imageBytes = widget.imageBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (imageBytes != null)
          _buildPhotoHeader(theme, imageBytes)
        else
          _buildTextHeader(theme),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ),
            if (widget.onLogManuallyInstead != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: widget.onLogManuallyInstead,
                  child: const Text('Log manually instead'),
                ),
              ),
            ],
          ],
        ),
        if (widget.showItemsSkeleton) ...[
          const SizedBox(height: 16),
          Text('Items', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Shimmer.fromColors(
            baseColor: base,
            highlightColor: highlight,
            child: const Column(
              children: [
                _SkeletonRow(),
                SizedBox(height: 10),
                _SkeletonRow(),
                SizedBox(height: 10),
                _SkeletonRow(),
                SizedBox(height: 10),
                _SkeletonRow(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Text-only header for the describe-a-meal path — the same "working" copy,
  /// rotating hint, and taking-long reassurance as the photo overlay, minus the
  /// photo. A small inline spinner gives motion while the item skeleton below
  /// carries the primary loading affordance.
  Widget _buildTextHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimating your meal…',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.hintText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.isTakingLong) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Still working—network may be slow.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoHeader(ThemeData theme, Uint8List imageBytes) {
    return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                height: 220,
                width: double.infinity,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final t = _controller.value;
                      final sweepY = -1.2 + (2.4 * t);
                      const sweepHeight = 0.22;
                      return Stack(
                        children: [
                          Container(
                            color: theme.colorScheme.surface.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.10
                                  : 0.06,
                            ),
                          ),
                          Align(
                            alignment: Alignment(0, sweepY),
                            child: FractionallySizedBox(
                              heightFactor: sweepHeight,
                              widthFactor: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      theme.colorScheme.primary.withValues(
                                        alpha: 0,
                                      ),
                                      theme.colorScheme.primary.withValues(
                                        alpha:
                                            theme.brightness == Brightness.dark
                                            ? 0.26
                                            : 0.16,
                                      ),
                                      theme.colorScheme.primary.withValues(
                                        alpha: 0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.78 : 0.86,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanning your meal…',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.hintText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (widget.isTakingLong) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Still working—network may be slow.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
