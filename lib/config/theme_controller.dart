import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's light/dark/system choice and persists it. The whole app
/// listens to this so a toggle rebuilds everything with the new brightness.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static const _prefsKey = 'theme_mode';

  /// Loads the saved choice (defaults to system) before the app is shown.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = _decode(prefs.getString(_prefsKey));
    } catch (_) {
      // Storage unavailable — fall back to following the system theme.
      value = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(mode));
    } catch (_) {
      // Persisting failed; the choice still applies for this session.
    }
  }

  /// Cycles System → Light → Dark → System, for a single toggle button.
  Future<void> cycle() {
    final next = switch (value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    return setMode(next);
  }

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  static ThemeMode _decode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/// The single app-wide instance, created in main().
final themeController = ThemeController();
