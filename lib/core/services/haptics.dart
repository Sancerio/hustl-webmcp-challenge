import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import 'preferences_service.dart';

/// Centralized haptics helper that respects user preferences.
class Haptics {
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static PreferencesService? _tryPrefs() {
    try {
      return GetIt.I<PreferencesService>();
    } catch (_) {
      return null;
    }
  }

  static bool _isEnabled() {
    final prefs = _tryPrefs();
    // Default to enabled when prefs not available yet
    return prefs?.hapticsEnabled ?? true;
  }

  static Future<void> maybeMediumImpact() async {
    if (!_isEnabled()) return;
    try {
      if (_isAndroid) {
        // Many Android devices ignore mediumImpact; selectionClick is more reliable
        await HapticFeedback.selectionClick();
      } else if (_isIOS) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (_) {
      // Non-critical: ignore haptic errors
    }
  }

  static Future<void> maybeSelectionClick() async {
    if (!_isEnabled()) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Non-critical: ignore haptic errors
    }
  }

  static Future<void> maybeLightImpact() async {
    if (!_isEnabled()) return;
    try {
      if (_isAndroid) {
        // Light impact maps poorly on Android; prefer selection click
        await HapticFeedback.selectionClick();
      } else if (_isIOS) {
        await HapticFeedback.lightImpact();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (_) {
      // Non-critical: ignore haptic errors
    }
  }

  // --- Design-system haptic vocabulary (spec §2.4) ---
  // Every haptic must be paired with a visible change at the call site; these
  // wrappers only fire the feedback, never decorate without a visual cue.

  /// Tap / toggle selection. Maps to [HapticFeedback.selectionClick].
  static Future<void> selection() => maybeSelectionClick();

  /// Confirmation of a committed action (e.g. a set logged).
  /// Maps to a medium impact (selection click on Android for reliability).
  static Future<void> confirm() => maybeMediumImpact();

  /// Celebration moment (PR, workout finished). Maps to a heavy impact.
  static Future<void> celebrate() async {
    if (!_isEnabled()) return;
    try {
      if (_isAndroid) {
        // Heavy impact is unreliable on many Android devices; fire a vibrate
        // for a noticeably stronger cue than selection click.
        await HapticFeedback.vibrate();
      } else if (_isIOS) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (_) {
      // Non-critical: ignore haptic errors
    }
  }
}
