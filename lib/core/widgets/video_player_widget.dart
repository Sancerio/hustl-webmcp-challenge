import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoPlayerWidget extends StatelessWidget {
  final String videoUrl;

  const VideoPlayerWidget({super.key, required this.videoUrl});

  // Check if the URL is a YouTube link
  bool get _isYoutubeUrl {
    return videoUrl.contains('youtube.com') || videoUrl.contains('youtu.be');
  }

  // Extract YouTube video ID from URL
  String? _getYoutubeVideoId() {
    if (!_isYoutubeUrl) return null;

    RegExp regExp;
    if (videoUrl.contains('youtu.be')) {
      regExp = RegExp(r'^https:\/\/youtu\.be\/([a-zA-Z0-9_-]{11})');
    } else {
      regExp = RegExp(
        r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
      );
    }

    final match = regExp.firstMatch(videoUrl);
    return match?.group(7) ?? match?.group(1);
  }

  // Generate YouTube thumbnail URL
  String? _getYoutubeThumbnailUrl() {
    final videoId = _getYoutubeVideoId();
    if (videoId == null) return null;
    return 'https://img.youtube.com/vi/$videoId/0.jpg';
  }

  // Launch YouTube video
  Future<void> _launchYoutubeVideo() async {
    final Uri url = Uri.parse(videoUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isYoutubeUrl) {
      // If YouTube URL, show thumbnail with play button
      return InkWell(
        onTap: _launchYoutubeVideo,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // YouTube thumbnail
            _getYoutubeThumbnailUrl() != null
                ? Image.network(
                    _getYoutubeThumbnailUrl()!,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.videocam_off, size: 50),
                      ),
                    ),
                  )
                : Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.image_not_supported, size: 50),
                    ),
                  ),

            // Play button overlay
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.play_arrow,
                color: Theme.of(context).colorScheme.onError,
                size: 40,
              ),
            ),

            // "Watch on YouTube" text at bottom
            Positioned(
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.scrim.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_circle_filled,
                      color: Theme.of(context).colorScheme.error,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Watch on YouTube',
                      style: TextStyle(
                        color: AppColors.brandCloudWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // For non-YouTube videos, we'd implement a video player
      // For now, just show a placeholder that would launch the video
      return InkWell(
        onTap: () async {
          final Uri url = Uri.parse(videoUrl);
          if (!await launchUrl(url)) {
            throw Exception('Could not launch $url');
          }
        },
        child: Container(
          color: colorScheme.surfaceContainerHighest,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_fill,
                  size: 60,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tap to play video',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
