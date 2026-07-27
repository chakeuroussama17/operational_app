/// Data types for the Machining module's incremental logging API.
///
/// One level deeper than Casting/Secondary: Customer -> Part -> Line -> entry
/// (keyed by Customer + PartNo + Line + shift-date). Shift-aware like the
/// others (Day 8AM-6PM / Night 8PM-6AM crossing midnight), MO number per part,
/// and each time slot also carries a Rejection count alongside Output and its
/// computed LOR%.
library;

/// One of the six checkpoints logged for a given shift.
class MachiningSlot {
  const MachiningSlot(
    this.label,
    this.outputKey,
    this.lorKey,
    this.rejectionKey,
  );

  final String label;

  /// Column/field name of the user-entered output, e.g. "Output_10AM".
  final String outputKey;

  /// Column/field name of the backend-computed LOR%, e.g. "Output_LOR10AM".
  final String lorKey;

  /// Column/field name of the user-entered rejection count, e.g. "Rejection_10AM".
  final String rejectionKey;
}

/// Day shift: 8AM-6PM.
const List<MachiningSlot> machiningDaySlots = [
  MachiningSlot('8 AM', 'Output_8AM', 'Output_LOR8AM', 'Rejection_8AM'),
  MachiningSlot('10 AM', 'Output_10AM', 'Output_LOR10AM', 'Rejection_10AM'),
  MachiningSlot('12 PM', 'Output_12PM', 'Output_LOR12PM', 'Rejection_12PM'),
  MachiningSlot('2 PM', 'Output_2PM', 'Output_LOR2PM', 'Rejection_2PM'),
  MachiningSlot('4 PM', 'Output_4PM', 'Output_LOR4PM', 'Rejection_4PM'),
  MachiningSlot('6 PM', 'Output_6PM', 'Output_LOR6PM', 'Rejection_6PM'),
];

/// Night shift: 8PM-6AM, crossing midnight.
const List<MachiningSlot> machiningNightSlots = [
  MachiningSlot('8 PM', 'Output_8PM', 'Output_LOR8PM', 'Rejection_8PM'),
  MachiningSlot('10 PM', 'Output_10PM', 'Output_LOR10PM', 'Rejection_10PM'),
  MachiningSlot('12 AM', 'Output_12AM', 'Output_LOR12AM', 'Rejection_12AM'),
  MachiningSlot('2 AM', 'Output_2AM', 'Output_LOR2AM', 'Rejection_2AM'),
  MachiningSlot('4 AM', 'Output_4AM', 'Output_LOR4AM', 'Rejection_4AM'),
  MachiningSlot('6 AM', 'Output_6AM', 'Output_LOR6AM', 'Rejection_6AM'),
];

List<MachiningSlot> machiningSlotsForShift(String shift) =>
    shift == 'Night' ? machiningNightSlots : machiningDaySlots;

/// Guesses the active shift from wall-clock time: Day runs 8AM-8PM, Night
/// runs 8PM-8AM. Only a starting-point default — the supervisor can always
/// override it (e.g. logging a late entry after shift changeover).
String autoDetectMachiningShift() {
  final hour = DateTime.now().hour;
  return (hour >= 8 && hour < 20) ? 'Day' : 'Night';
}

/// Dashboard card: one customer and when it was last logged today.
class CustomerStatus {
  const CustomerStatus({required this.customer, this.lastUpdated});

  final String customer;
  final String? lastUpdated; // "HH:mm" or null when nothing logged today

  factory CustomerStatus.fromJson(Map<String, dynamic> json) => CustomerStatus(
    customer: cleanCell(json['dcm']) ?? '',
    lastUpdated: cleanCell(json['lastUpdated']),
  );
}

/// Part selector card: one part of a customer, with its current MO
/// (manufacturing order) number. A navigation step to the Line selector below
/// it, so it carries no fill percentage of its own.
class MachiningPartStatus {
  const MachiningPartStatus({required this.part, this.mo, this.lastUpdated});

  final String part;
  final String? mo;
  final String? lastUpdated;

  factory MachiningPartStatus.fromJson(Map<String, dynamic> json) =>
      MachiningPartStatus(
        part: cleanCell(json['part']) ?? '',
        mo: cleanCell(json['mo']),
        lastUpdated: cleanCell(json['lastUpdated']),
      );
}

/// Line selector card: one line of a customer + part, with today's
/// completion level. This is the level that opens the entry form.
class MachiningLineStatus {
  const MachiningLineStatus({
    required this.line,
    this.lastUpdated,
    required this.fillPercent,
  });

  final String line;
  final String? lastUpdated;

  /// 0-100: how many of the six time slots are filled today.
  final int fillPercent;

  factory MachiningLineStatus.fromJson(Map<String, dynamic> json) {
    final raw = num.tryParse(json['fillPercent']?.toString() ?? '') ?? 0;
    return MachiningLineStatus(
      line: cleanCell(json['part']) ?? '',
      lastUpdated: cleanCell(json['lastUpdated']),
      fillPercent: raw.clamp(0, 100).round(),
    );
  }
}

/// Today's saved row for a Customer + Part + Line. Field access is by
/// column name so the row survives backend column additions untouched.
class MachiningRow {
  const MachiningRow(this.raw);

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
