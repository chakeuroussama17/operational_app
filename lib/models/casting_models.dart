/// Data types for the Casting module's incremental logging API.
///
/// Casting is shift-aware (Day 8AM-6PM / Night 8PM-6AM, crossing midnight) —
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

  /// Column/field name of the user-entered output, e.g. "Output_10AM".
  final String outputKey;

  /// Column/field name of the backend-computed LOR%, e.g. "Output_LOR10AM".
  final String lorKey;
}

/// Day shift: 8AM-6PM.
const List<CastingSlot> castingDaySlots = [
  CastingSlot('8 AM', 'Output_8AM', 'Output_LOR8AM'),
  CastingSlot('10 AM', 'Output_10AM', 'Output_LOR10AM'),
  CastingSlot('12 PM', 'Output_12PM', 'Output_LOR12PM'),
  CastingSlot('2 PM', 'Output_2PM', 'Output_LOR2PM'),
  CastingSlot('4 PM', 'Output_4PM', 'Output_LOR4PM'),
  CastingSlot('6 PM', 'Output_6PM', 'Output_LOR6PM'),
];

/// Night shift: 8PM-6AM, crossing midnight.
const List<CastingSlot> castingNightSlots = [
  CastingSlot('8 PM', 'Output_8PM', 'Output_LOR8PM'),
  CastingSlot('10 PM', 'Output_10PM', 'Output_LOR10PM'),
  CastingSlot('12 AM', 'Output_12AM', 'Output_LOR12AM'),
  CastingSlot('2 AM', 'Output_2AM', 'Output_LOR2AM'),
  CastingSlot('4 AM', 'Output_4AM', 'Output_LOR4AM'),
  CastingSlot('6 AM', 'Output_6AM', 'Output_LOR6AM'),
];

List<CastingSlot> castingSlotsForShift(String shift) =>
    shift == 'Night' ? castingNightSlots : castingDaySlots;

/// Guesses the active shift from wall-clock time: Day runs 8AM-8PM, Night
/// runs 8PM-8AM. Only a starting-point default — the supervisor can always
/// override it (e.g. logging a late entry after shift changeover).
String autoDetectCastingShift() {
  final hour = DateTime.now().hour;
  return (hour >= 8 && hour < 20) ? 'Day' : 'Night';
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

  /// 0-100: how many of this shift's six time slots are filled today.
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
