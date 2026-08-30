import 'package:flutter/material.dart';
import 'preferences_service.dart';

/// Handles app theme selection and persistence.
///
/// Exposes a `ValueNotifier<ThemeMode>` for reactive UI updates and persists
/// changes to `PreferencesService` so the user's choice is remembered.
class ThemeService {
  /// Raw string values used when persisting theme mode.
  static const String rawSystem = 'system';
  static const String rawLight = 'light';
  static const String rawDark = 'dark';

  final PreferencesService _prefs;

  /// Current theme mode. Listen to receive updates when the theme changes.
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  ThemeService(this._prefs);

  /// Initialize the theme by reading the persisted raw mode and mapping it
  /// to a [ThemeMode]. Should be awaited before building the app UI.
  Future<void> init() async {
    final raw = await _prefs.getRawThemeMode();
    themeMode.value = _fromRaw(raw);
  }

  /// Update the theme and persist the user's preference.
  ///
  /// In case persistence fails, reverts the in-memory value to the previous
  /// theme to avoid UI inconsistency.
  Future<void> setThemeMode(ThemeMode mode) async {
    final previous = themeMode.value;
    themeMode.value = mode;
    try {
      await _prefs.setRawThemeMode(_toRaw(mode));
    } catch (_) {
      // Revert to previous mode on failure to persist
      themeMode.value = previous;
    }
  }

  ThemeMode _fromRaw(String raw) {
    switch (raw) {
      case rawLight:
        return ThemeMode.light;
      case rawDark:
        return ThemeMode.dark;
      case rawSystem:
      default:
        return ThemeMode.system;
    }
  }

  String _toRaw(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return rawLight;
      case ThemeMode.dark:
        return rawDark;
      case ThemeMode.system:
        return rawSystem;
    }
  }
}
