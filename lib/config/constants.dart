import 'package:flutter/material.dart';

/// Unified Apps Script Web App backend (Code.gs). Handles the incremental
/// dashboard/parts/row GETs and the upsert POST for all three modules, routed
/// by a `module` field ("casting" | "secondary" | "machining").
// ignore: constant_identifier_names
const String CASTING_WEBHOOK_URL =
    'https://script.google.com/macros/s/AKfycbwLwOydrgkSuIsUt3329z2CrFV8jAooqC7bzoEgj7vnDtebzi4uH3YnWK_1yT2z8DD3Dw/exec';

/// Any email may sign in — the company-domain restriction was removed so
/// contractors and people without an @hidsb.com mailbox can log from the
/// floor. What gates access instead is the Users tab: a new registration
/// lands INACTIVE and an admin switches it on, so the address someone signs
/// up with proves nothing on its own.
///
/// Only the shape is checked here, to catch a typo before Firebase is called.
bool looksLikeEmail(String email) {
  final trimmed = email.trim();
  final at = trimmed.indexOf('@');
  if (at <= 0 || at != trimmed.lastIndexOf('@')) return false;
  final domain = trimmed.substring(at + 1);
  return domain.contains('.') &&
      !domain.startsWith('.') &&
      !domain.endsWith('.') &&
      !trimmed.contains(' ');
}

/// Sees every department and every dashboard. Everyone else is confined to
/// the one department on their Users row. The backend enforces this too —
/// this constant only decides what the app bothers to show.
const String adminEmail = 'admin@hidsb.com';

/// The three production departments, in the order they appear everywhere.
/// Each maps 1:1 to a module ('Casting' -> 'casting').
const List<String> departments = ['Casting', 'Secondary', 'Machining'];

/// The casting bay's machines, in plant order. A DCM is a die-casting machine;
/// WELD is not one, but it logs output the same way so it sits in the same
/// list. The numbering has gaps (no 09, 10, 13, 14, 16, 22) — those machines
/// don't exist, so the list is written out rather than generated.
///
/// Adding a DCM picks from here instead of typing, so a machine can't enter
/// the sheet as "DCM8" one shift and "dcm 08" the next. Retiring or
/// commissioning a machine means editing this list and shipping a build.
const List<String> castingMachines = [
  'DCM08',
  'DCM11',
  'DCM12',
  'DCM15',
  'DCM17',
  'DCM18',
  'DCM19',
  'DCM20',
  'DCM21',
  'DCM23',
  'DCM24',
  'DCM25',
  'DCM26',
  'DCM27',
  'DCM28',
  'DCM29',
  'DCM30',
  'DCM31',
  'DCM32',
  'DCM33',
  'WELD',
];

/// The secondary bay's finishing stations, in plant order. Trimming presses
/// (TRIM01-09) and de-flashing robots (ROBO01-04) are numbered; the rest are
/// named for what they do. Picked from rather than typed, for the same reason
/// as [castingMachines].
///
/// SHOTB-BT and SHOTB-GR are the full names, not abbreviations of longer ones.
const List<String> secondaryStations = [
  'CURING',
  'FETTLING',
  'ROBO01',
  'ROBO02',
  'ROBO03',
  'ROBO04',
  'SHOTB-BT',
  'SHOTB-GR',
  'TRIM01',
  'TRIM02',
  'TRIM03',
  'TRIM04',
  'TRIM05',
  'TRIM06',
  'TRIM07',
  'TRIM08',
  'TRIM09',
  'TUMBLING',
];

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

  // --- The magenta->violet accent, from the company's supplied auth mockup.
  // Started life on login/sign-up; now also carries the app bar rule, the
  // home hero and every gradient icon chip, so the whole app reads as one
  // palette rather than a branded cover bolted onto a navy app. ---
  static const Color authPink = Color(0xFFE91E63);
  static const Color authViolet = Color(0xFF7C3AED);
  static const LinearGradient authGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [authPink, authViolet],
  );

  /// The app bar's own gradient — the logo purple deepened, so the pink rule
  /// beneath it has something dark to sit against in either mode.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B2F7F), Color(0xFF241C52)],
  );

  /// The Log tab's backdrop wash. Dark keeps the login's mood; light is the
  /// same hue drained to near-white so day mode is genuinely light rather
  /// than a dimmed dark theme.
  static List<Color> get homeBackdrop => _dark
      ? const [Color(0xFF1B1430), Color(0xFF120E1F), Color(0xFF0B0913)]
      : const [Color(0xFFF7F5FC), Color(0xFFF1EDFA), Color(0xFFE8E3F5)];

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

  // --- Dashboard chart chrome ---
  //
  // Gridlines/axes reuse the app's own neutral tokens (already validated for
  // contrast and already flip with brightness) rather than inventing a
  // parallel set. Chart surfaces sit on the same card surface as everything
  // else in the app.
  static Color get chartGrid => borderSubtle;
  static Color get chartAxisLabel => textSecondary;

  /// For the emphasis pattern: the one mark that matters keeps its hue, the
  /// rest recede to this. Not a series color — never assign it as identity.
  static Color get chartMuted =>
      _dark ? const Color(0xFF4A4463) : const Color(0xFFC3BFD6);

  /// Fixed-order, colorblind-safe 8-hue set for telling distinct identities
  /// apart (currently: rejection defect types). Assigned by POSITION in this
  /// list, never generated or cycled — a 9th distinct value folds into
  /// "Other" rather than reusing or inventing a hue. Validated against both
  /// a light and a dark chart surface (OKLab CVD-separation + contrast); see
  /// the project's data-viz reference palette for the source values.
  static const List<Color> categorical = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
    Color(0xFFE34948), // red
  ];
  static const List<Color> _categoricalDark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];
  static List<Color> get categoricalOf =>
      _dark ? _categoricalDark : categorical;
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
