/// Data types for the Secondary module's incremental logging API.
///
/// Mirrors Casting (shift-aware, Day 8AM-6PM / Night 8PM-6AM crossing
/// midnight, MO number per part) but with different column names:
///   DCM → Station, Output_* → Actual_*, Output_LOR* → LOR_*
library;

/// One of the six checkpoints logged for a given shift.
class SecondarySlot {
  const SecondarySlot(this.label, this.actualKey, this.lorKey);

  final String label;

  /// Column/field name of the user-entered actual, e.g. "Actual_10AM".
  final String actualKey;

  /// Column/field name of the backend-computed LOR%, e.g. "LOR_10AM".
  final String lorKey;
}

/// Day shift: 8AM-6PM.
const List<SecondarySlot> secondaryDaySlots = [
  SecondarySlot('8 AM', 'Actual_8AM', 'LOR_8AM'),
  SecondarySlot('10 AM', 'Actual_10AM', 'LOR_10AM'),
  SecondarySlot('12 PM', 'Actual_12PM', 'LOR_12PM'),
  SecondarySlot('2 PM', 'Actual_2PM', 'LOR_2PM'),
  SecondarySlot('4 PM', 'Actual_4PM', 'LOR_4PM'),
  SecondarySlot('6 PM', 'Actual_6PM', 'LOR_6PM'),
];

/// Night shift: 8PM-6AM, crossing midnight.
const List<SecondarySlot> secondaryNightSlots = [
  SecondarySlot('8 PM', 'Actual_8PM', 'LOR_8PM'),
  SecondarySlot('10 PM', 'Actual_10PM', 'LOR_10PM'),
  SecondarySlot('12 AM', 'Actual_12AM', 'LOR_12AM'),
  SecondarySlot('2 AM', 'Actual_2AM', 'LOR_2AM'),
  SecondarySlot('4 AM', 'Actual_4AM', 'LOR_4AM'),
  SecondarySlot('6 AM', 'Actual_6AM', 'LOR_6AM'),
];

List<SecondarySlot> secondarySlotsForShift(String shift) =>
    shift == 'Night' ? secondaryNightSlots : secondaryDaySlots;

/// Guesses the active shift from wall-clock time: Day runs 8AM-8PM, Night
/// runs 8PM-8AM. Only a starting-point default — the supervisor can always
/// override it (e.g. logging a late entry after shift changeover).
String autoDetectSecondaryShift() {
  final hour = DateTime.now().hour;
  return (hour >= 8 && hour < 20) ? 'Day' : 'Night';
}

/// Dashboard card: one Station and when it was last logged today.
class StationStatus {
  const StationStatus({required this.station, this.lastUpdated});

  final String station;
  final String? lastUpdated; // "HH:mm" or null when nothing logged today

  factory StationStatus.fromJson(Map<String, dynamic> json) => StationStatus(
    station: cleanCell(json['dcm']) ?? '',
    lastUpdated: cleanCell(json['lastUpdated']),
  );
}

/// Part selector card: one part of a Station, with this shift's completion
/// level and the part's current MO (manufacturing order) number.
class SecondaryPartStatus {
  const SecondaryPartStatus({
    required this.part,
    this.mo,
    this.name,
    this.lastUpdated,
    required this.fillPercent,
  });

  /// The part CODE (chosen from the master list) — this card's title.
  final String part;
  final String? mo;

  /// Human-readable part name from the master list.
  final String? name;
  final String? lastUpdated;

  /// 0-100: how many of this shift's six time slots are filled today.
  final int fillPercent;

  factory SecondaryPartStatus.fromJson(Map<String, dynamic> json) {
    final raw = num.tryParse(json['fillPercent']?.toString() ?? '') ?? 0;
    return SecondaryPartStatus(
      part: cleanCell(json['part']) ?? '',
      mo: cleanCell(json['mo']),
      name: cleanCell(json['name']),
      lastUpdated: cleanCell(json['lastUpdated']),
      fillPercent: raw.clamp(0, 100).round(),
    );
  }
}

/// Today's saved row for a Station + Part. Field access is by column name.
class SecondaryRow {
  const SecondaryRow(this.raw);

  final Map<String, dynamic> raw;

  /// Cell as a display/edit string, or null when empty. "300.0" -> "300".
  String? value(String key) => cleanCell(raw[key]);

  /// LOR cell formatted for the read-only badge, e.g. "10%".
  /// Google Sheets stores "10%" as fraction 0.1, so scale by 100.
  String? lorLabel(String lorKey) {
    final cell = raw[lorKey];
    if (cell == null) return null;
    final s = cell.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    if (s.endsWith('%')) return s;
    final n = num.tryParse(s);
    if (n == null) return null;
    final pct = n * 100;
    final rounded = (pct * 10).round() / 10;
    final label = rounded % 1 == 0
        ? rounded.toInt().toString()
        : rounded.toString();
    return '$label%';
  }
}

/// Normalises a JSON/Sheets cell: null/blank/"null" -> null, and
/// integer-valued numbers lose their trailing ".0".
String? cleanCell(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  final n = num.tryParse(s);
  if (n != null && n % 1 == 0) return n.toInt().toString();
  return s;
}
