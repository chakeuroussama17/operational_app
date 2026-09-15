/// Data types for the Casting module's incremental logging API.
///
/// Casting is shift-aware (Day 10AM-8PM / Night 10PM-8AM, crossing midnight) —
/// the only module with this schema; Secondary/Machining are unchanged. The
/// backend exposes (all on the webhook URL):
///   GET  ?action=dashboard&shift=Z             -> [DcmStatus]
///   GET  ?action=parts&dcm=X&shift=Z           -> [PartStatus]
///   GET  ?action=row&dcm=X&part=Y&shift=Z      -> CastingRow | null
///   POST {secret, module:'casting', data: {DCM, PartNo, Shift, ...changed}}
library;

/// One of the six checkpoints logged for a given shift.
class CastingSlot {
  const CastingSlot(this.label, this.outputKey, this.lorKey);

  final String label;

  /// Column/field name of the user-entered count, e.g. "Actual_10AM".
  final String outputKey;

  /// Column/field name of the backend-computed LOR%, e.g. "LOR_10AM".
  final String lorKey;
}

/// Day shift: 10AM-8PM, logged every 4 hours.
const List<CastingSlot> castingDaySlots = [
  CastingSlot('12 PM', 'Actual_12PM', 'LOR_12PM'),
  CastingSlot('4 PM', 'Actual_4PM', 'LOR_4PM'),
  CastingSlot('7:30 PM', 'Actual_7_30PM', 'LOR_7_30PM'),
];

/// Night shift: 10PM-8AM, logged every 4 hours.
const List<CastingSlot> castingNightSlots = [
  CastingSlot('12 AM', 'Actual_12AM', 'LOR_12AM'),
  CastingSlot('4 AM', 'Actual_4AM', 'LOR_4AM'),
  CastingSlot('7:30 AM', 'Actual_7_30AM', 'LOR_7_30AM'),
];

List<CastingSlot> castingSlotsForShift(String shift) =>
    shift == 'Night' ? castingNightSlots : castingDaySlots;

/// Day runs from 10:00 through 21:59; Night takes over at 22:00.
String autoDetectCastingShift() {
  final hour = DateTime.now().hour;
  return (hour >= 10 && hour < 22) ? 'Day' : 'Night';
}

/// Dashboard card: one DCM machine and when it was last logged this shift.
class DcmStatus {
  const DcmStatus({required this.dcm, this.lastUpdated});

  final String dcm;
  final String? lastUpdated; // "HH:mm" or null when nothing logged this shift

  factory DcmStatus.fromJson(Map<String, dynamic> json) => DcmStatus(
    dcm: cleanCell(json['dcm']) ?? '',
    lastUpdated: cleanCell(json['lastUpdated']),
  );
}

/// Part selector card: one part of a DCM, with this shift's completion
/// level and the part's current MO (manufacturing order) number.
class PartStatus {
  const PartStatus({
    required this.part,
    this.mo,
    this.name,
    this.lastUpdated,
    required this.fillPercent,
  });

  /// The part CODE (chosen from the master list) — this card's title.
  final String part;
  final String? mo;

  /// Human-readable part name from the master list (e.g. "…-CRANKCASE-1-CAST").
  final String? name;
  final String? lastUpdated;

  /// 0-100: how many of this shift's three checkpoints are filled today.
  final int fillPercent;

  factory PartStatus.fromJson(Map<String, dynamic> json) {
    final raw = num.tryParse(json['fillPercent']?.toString() ?? '') ?? 0;
    return PartStatus(
      part: cleanCell(json['part']) ?? '',
      mo: cleanCell(json['mo']),
      name: cleanCell(json['name']),
      lastUpdated: cleanCell(json['lastUpdated']),
      fillPercent: raw.clamp(0, 100).round(),
    );
  }
}

/// This shift's saved row for a DCM + Part. Field access is by column name
/// so the row survives backend column additions untouched.
class CastingRow {
  const CastingRow(this.raw);

  final Map<String, dynamic> raw;

  /// Cell as a display/edit string, or null when empty. "300.0" -> "300".
  String? value(String key) => cleanCell(raw[key]);

  /// LOR cell formatted for the read-only badge, e.g. "10%".
  ///
  /// Google Sheets stores a written "10%" as the fraction 0.1 (the cell keeps
  /// percent formatting), so a numeric value is a fraction and is scaled by
  /// 100. An explicit "10%" string is returned unchanged.
  String? lorLabel(String lorKey) {
    final cell = raw[lorKey];
    if (cell == null) return null;
    final s = cell.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    if (s.endsWith('%')) return s;
    final n = num.tryParse(s);
    if (n == null) return null;
    final pct = n * 100;
    // Round to at most one decimal and drop a trailing ".0".
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
