import 'package:flutter/material.dart';

/// Unified Apps Script Web App backend (Code.gs). Handles the incremental
/// dashboard/parts(/lines)/row GETs and the upsert POST for all three
/// modules, routed by a `module` field ("casting" | "secondary" | "machining").
// ignore: constant_identifier_names
const String CASTING_WEBHOOK_URL =
    'https://script.google.com/macros/s/AKfycbyWXgKCOGKnhCWAXV0AFBQGyz-FQLAXVNxkzEcpC4XSgHCQwc9hRyKFzMU5cY0lxcXXAQ/exec';

/// Company email domains allowed to sign in / register. Anything else is
/// refused before Firebase is even called.
const List<String> allowedEmailDomains = [
  '@hidsb.com',
  '@hicom-engineering.com',
];

/// Sees every department and every dashboard. Everyone else is confined to
/// the one department on their Users row. The backend enforces this too —
/// this constant only decides what the app bothers to show.
const String adminEmail = 'admin@hidsb.com';

/// The three production departments, in the order they appear everywhere.
/// Each maps 1:1 to a module ('Casting' -> 'casting').
const List<String> departments = ['Casting', 'Secondary', 'Machining'];

/// Shared secret checked by the Apps Script doPost (its SECRET_KEY).
/// Sent as a top-level "secret" field with every submission.
// ignore: constant_identifier_names
const String SHEETS_SHARED_SECRET = 'hicom2026changeme';

/// HICOM brand palette, built around the logo's indigo-purple (sampled
/// directly from assets/logo.png) with a gold accent for CTAs — the classic
/// premium purple/gold pairing.
///
/// The brand accents (navy/steelBlue/amber/success/danger) are the same in
/// both light and dark mode and stay `const`. The neutral surfaces and text
/// FLIP with [brightness] — they are getters, so any widget that rebuilds
/// after a theme change picks up the new value. [brightness] is kept in sync
/// with the active ThemeData by the root App widget in main.dart.
abstract class AppColors {
  /// Set by the root App widget whenever the effective theme changes.
  static Brightness brightness = Brightness.light;
  static bool get _dark => brightness == Brightness.dark;

  // --- Brand accents (identical in both modes) ---
  static const Color navy = Color(0xFF383287); // primary / header (logo purple)
  static const Color navyDark = Color(0xFF241F5E); // gradients / pressed states
  static const Color steelBlue = Color(
    0xFF6C63B5,
  ); // secondary emphasis / focus
  static const Color amber = Color(0xFFFFA000); // CTA / highlights (gold)
  // Amber is a background colour; this is the readable-on-surface version of
  // it, for text marking an unsaved edit.
  static const Color amberDark = Color(0xFFB26A00);
  static const Color success = Color(0xFF2E7D32);
  static const Color danger = Color(0xFFC62828);

  // --- Neutrals (flip with brightness) ---
  static Color get background =>
      _dark ? const Color(0xFF131120) : const Color(0xFFF6F5FA);
  static Color get surface => _dark ? const Color(0xFF211E30) : Colors.white;
  static Color get surfaceTint =>
      _dark ? const Color(0xFF2C2842) : const Color(0xFFEDEBF7);
  static Color get textPrimary =>
      _dark ? const Color(0xFFECEAF6) : const Color(0xFF211D3D);
  static Color get textSecondary =>
      _dark ? const Color(0xFF9E97B8) : const Color(0xFF6E6688);
  static Color get borderSubtle =>
      _dark ? const Color(0xFF322D47) : const Color(0xFFE1DEEE);

  /// Explicit neutral values for a given brightness, used to build the two
  /// ThemeData objects up front (where a single global getter won't do).
  static Color backgroundOf(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF131120) : const Color(0xFFF6F5FA);
  static Color surfaceOf(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF211E30) : Colors.white;
  static Color textPrimaryOf(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFECEAF6) : const Color(0xFF211D3D);
  static Color borderOf(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF322D47) : const Color(0xFFC6D0DA);
}

/// Shared sizing for large, glove-friendly touch targets.
abstract class AppDimens {
  static const double fieldFontSize = 18;
  static const double labelFontSize = 15;
  static const double buttonHeight = 60;
  static const double fieldSpacing = 18;
  static const double screenPadding = 20;
  static const double cardRadius = 14;
}
