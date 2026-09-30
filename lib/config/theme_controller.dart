import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's system/light/dark/floor choice and persists it. The whole
/// app listens to this so a toggle rebuilds everything with the new look.
///
/// Floor mode is dark underneath — [value] reads [ThemeMode.dark] — with
/// [floor] set: maximum contrast and larger text, for reading a phone at arm's
/// length under factory lighting. It is a fourth stop on the same toggle
/// rather than a separate switch, so the bar does not grow another button.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static const _prefsKey = 'theme_mode';

  bool _floor = false;

  /// High contrast and larger text. Only ever true while [value] is dark.
  bool get floor => _floor;

  /// Setting a mode directly always leaves floor mode — so a plain
  /// "go to dark" can never quietly keep the high-contrast palette.
  @override
  set value(ThemeMode mode) {
    final wasFloor = _floor;
    _floor = false;
    if (mode == super.value && wasFloor) {
      notifyListeners();
    } else {
      super.value = mode;
    }
  }

  /// Loads the saved choice (defaults to system) before the app is shown.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == 'floor') {
        _setFloor();
      } else {
        value = _decode(raw);
      }
    } catch (_) {
      // Storage unavailable — fall back to following the system theme.
      value = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value && !_floor) return;
    value = mode;
    await _save(_encode(mode));
  }

  Future<void> setFloor() async {
    _setFloor();
    await _save('floor');
  }

  void _setFloor() {
    final changed = !_floor || super.value != ThemeMode.dark;
    _floor = true;
    if (super.value != ThemeMode.dark) {
      super.value = ThemeMode.dark;
    } else if (changed) {
      notifyListeners();
    }
  }

  /// Cycles System → Light → Dark → Floor → System, for a single button.
  Future<void> cycle() {
    if (_floor) return setMode(ThemeMode.system);
    return switch (value) {
      ThemeMode.system => setMode(ThemeMode.light),
      ThemeMode.light => setMode(ThemeMode.dark),
      ThemeMode.dark => setFloor(),
    };
  }

  Future<void> _save(String raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, raw);
    } catch (_) {
      // Persisting failed; the choice still applies for this session.
    }
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
