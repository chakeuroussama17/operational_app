/// Data types for the Casting module's incremental logging API.
///
/// The backend exposes (all on the webhook URL):
///   GET  ?action=dashboard                    -> [DcmStatus]
///   GET  ?action=parts&dcm=X                  -> [PartStatus]
///   GET  ?action=row&dcm=X&part=Y&shift=Z     -> CastingRow | null
///   POST {secret, data: {DCM, PartNo, Shift, ...only changed fields}}
library;

/// One of the six fixed time slots logged per shift.
class CastingSlot {
  const CastingSlot(this.label, this.outputKey, this.lorKey);

  final String label;

  /// Column/field name of the user-entered output, e.g. "Output_10AM".
  final String outputKey;

  /// Column/field name of the backend-computed LOR%, e.g. "Output_LOR10AM".
  final String lorKey;
}

const List<CastingSlot> castingSlots = [
  CastingSlot('10 AM', 'Output_10AM', 'Output_LOR10AM'),
  CastingSlot('12 PM', 'Output_12PM', 'Output_LOR12PM'),
  CastingSlot('2 PM', 'Output_2PM', 'Output_LOR2PM'),
  CastingSlot('4 PM', 'Output_4PM', 'Output_LOR4PM'),
  CastingSlot('6 PM', 'Output_6PM', 'Output_LOR6PM'),
  CastingSlot('8 PM', 'Output_8PM', 'Output_LOR8PM'),
];

/// Dashboard card: one DCM machine and when it was last logged today.
class DcmStatus {
  const DcmStatus({required this.dcm, this.lastUpdated});

  final String dcm;
  final String? lastUpdated; // "HH:mm" or null when nothing logged today

  factory DcmStatus.fromJson(Map<String, dynamic> json) => DcmStatus(
    dcm: cleanCell(json['dcm']) ?? '',
    lastUpdated: cleanCell(json['lastUpdated']),
  );
}

/// Part selector card: one part of a DCM, with today's completion level.
class PartStatus {
  const PartStatus({
    required this.part,
    this.lastUpdated,
    required this.fillPercent,
  });

  final String part;
  final String? lastUpdated;

  /// 0-100: how many of the six time slots are filled today.
  final int fillPercent;

  factory PartStatus.fromJson(Map<String, dynamic> json) {
    final raw = num.tryParse(json['fillPercent']?.toString() ?? '') ?? 0;
    return PartStatus(
      part: cleanCell(json['part']) ?? '',
      lastUpdated: cleanCell(json['lastUpdated']),
      fillPercent: raw.clamp(0, 100).round(),
    );
  }
}

/// Today's saved row for a DCM + Part + Shift. Field access is by column
/// name so the row survives backend column additions untouched.
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
