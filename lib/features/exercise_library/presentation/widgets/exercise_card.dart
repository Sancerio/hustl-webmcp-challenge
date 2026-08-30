import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/app/theme/app_colors.dart';

class ExerciseCard extends StatelessWidget {
  final String exerciseName;
  final String muscleGroup;
  final DateTime? lastPerformed;
  final String? imageUrl;
  final VoidCallback? onTap;
  final String? heroTag;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final bool isLoading;

  const ExerciseCard({
    super.key,
    required this.exerciseName,
    required this.muscleGroup,
    this.lastPerformed,
    this.imageUrl,
    this.onTap,
    this.heroTag,
    this.showRefresh = false,
    this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.all(4),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize:
              MainAxisSize.min, // Make sure column only takes needed space
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Image area with improved handling
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: heroTag == null
                    ? _buildImageWithOverlay(context)
                    : Hero(
                        tag: heroTag!,
                        child: _buildImageWithOverlay(context),
                      ),
              ),
            ),

            // Text content with improved contrast
            const SizedBox(height: 8),
            Container(
              height: 90,
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // §12.4: card name = 15/w500 (bodyLarge), muted 12px meta.
                  Text(
                    exerciseName,
                    style: textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    muscleGroup,
                    style: textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (lastPerformed != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.yMMMd().format(lastPerformed!.toLocal()),
                      style: textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build the appropriate image widget
  Widget _buildImage(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(context);
    }

    // Check if it's an asset or network image
    if (imageUrl!.startsWith('assets/')) {
      return Image.asset(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context);
        },
      );
    } else {
      // Network image with caching and shimmer placeholder
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildShimmer(context),
        errorWidget: (context, url, error) => _buildPlaceholder(context),
      );
    }
  }

  Widget _buildImageWithOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final scrim = theme.colorScheme.scrim;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildImage(context),
        if (isLoading)
          Container(
            color: scrim.withValues(alpha: 0.35),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        if (showRefresh && !isLoading)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: scrim.withValues(alpha: 0.4),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.refresh),
                color: AppColors.brandCloudWhite,
                tooltip: 'Regenerate image',
                onPressed: onRefresh,
              ),
            ),
          ),
      ],
    );
  }

  // Helper method to build the placeholder widget with improved contrast
  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initials = _initialsFor(exerciseName);
    final bg = _colorForName(exerciseName, scheme);
    final fg = _foregroundFor(bg);

    return Container(
      color: scheme.surface,
      child: Center(
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  // Build two-letter initials from the exercise name
  String _initialsFor(String name) {
    final cleaned = name
        .replaceAll(RegExp(r"[()\[\]{}]"), ' ')
        .replaceAll(RegExp(r"\s+"), ' ')
        .trim();
    if (cleaned.isEmpty) return '#';
    final parts = cleaned.split(' ');
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2)
          ? (p.substring(0, 2)).toUpperCase()
          : p.substring(0, 1).toUpperCase();
    }
    final first = parts[0];
    final second = parts[1];
    final i1 = first.isNotEmpty ? first[0] : '';
    final i2 = second.isNotEmpty ? second[0] : '';
    final res = (i1 + i2).toUpperCase();
    return res.isNotEmpty ? res : '#';
  }

  // Deterministic background color based on the name
  Color _colorForName(String name, ColorScheme scheme) {
    final palette = <Color>[
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerHighest,
    ];
    final idx = name.toLowerCase().hashCode.abs() % palette.length;
    return palette[idx];
  }

  // Choose foreground color for contrast
  Color _foregroundFor(Color bg) {
    final brightness = ThemeData.estimateBrightnessForColor(bg);
    return brightness == Brightness.dark
        ? AppColors.brandCloudWhite
        : AppColors.brandCarbonBlack.withValues(alpha: 0.87);
  }

  Widget _buildShimmer(BuildContext context) {
    final theme = Theme.of(context);
    return Shimmer.fromColors(
      baseColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      highlightColor: theme.colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
