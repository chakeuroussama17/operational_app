/// The plant's downtime reason codes.
///
/// Fifteen of them, stable enough to ship with the app rather than be
/// configured — the same call [MachiningOperation] makes. The list is short on
/// purpose: it exists so a month of stoppages can be added up by cause, which
/// only works if everyone picks from the same words. [otherDowntimeReason] is
/// the escape hatch for a cause nobody anticipated, and what gets typed there
/// is stored verbatim.
library;

class DowntimeReason {
  const DowntimeReason(this.code, this.name);

  /// Zero-padded, as the plant writes it ("001", not "1").
  final String code;
  final String name;

  /// "008 · MACHINING MAINTENANCE DOWNTIME" — what the dropdown shows and,
  /// for a chosen reason, exactly what lands in the sheet cell. The code
  /// leads so `LEFT(cell, 3)` pulls it back out for a pivot.
  String get label => '$code · $name';
}

/// Not a real code — the sentinel the dropdown uses for "none of these".
/// Deliberately not three digits, so it can never collide with a real one.
const String otherDowntimeReasonCode = 'OTHER';

const DowntimeReason otherDowntimeReason = DowntimeReason(
  otherDowntimeReasonCode,
  'Other — type it in',
);

/// Ordered as the plant's own list is: casting causes, then machining, then
/// the scheduled non-production stops. Kept in that order rather than sorted,
/// because that's the order the people picking from it already know.
const List<DowntimeReason> downtimeReasons = [
  DowntimeReason('001', 'TOOL ROOM DOWNTIME'),
  DowntimeReason('002', 'DIE MAINTENANCE DOWNTIME'),
  DowntimeReason('003', 'CASTING ENGINEERING DOWNTIME'),
  DowntimeReason('004', 'CASTING MAINTENANCE DOWNTIME'),
  DowntimeReason('005', 'CASTING PRODUCTION DOWNTIME'),
  DowntimeReason('006', 'CASTING OTHERS DOWNTIME'),
  DowntimeReason('007', 'MACHINING ENGINEERING DOWNTIME'),
  DowntimeReason('008', 'MACHINING MAINTENANCE DOWNTIME'),
  DowntimeReason('009', 'PART SUPPLY DOWNTIME'),
  DowntimeReason('010', 'MACHINING PRODUCTION DOWNTIME'),
  DowntimeReason('011', 'MACHINING OTHERS DOWNTIME'),
  DowntimeReason('012', 'TEA BREAK'),
  DowntimeReason('013', 'LUNCH-DINNER BREAK'),
  DowntimeReason('014', 'END OF WORK'),
  DowntimeReason('015', 'COMPANY EVENT'),
];

/// The coded reason a stored cell holds, or null when it holds free text
/// (an "Other" reason, or anything written before the codes existed).
///
/// Matches on the whole label so a cell reading "001 · TOOL ROOM DOWNTIME"
/// comes back as a chosen code, while "waiting on the crane" doesn't.
DowntimeReason? downtimeReasonFromCell(String? cell) {
  final value = (cell ?? '').trim();
  if (value.isEmpty) return null;
  for (final reason in downtimeReasons) {
    if (reason.label.toLowerCase() == value.toLowerCase()) return reason;
  }
  // Tolerate a cell holding only the code, which is how someone editing the
  // sheet by hand would most likely write it.
  for (final reason in downtimeReasons) {
    if (reason.code == value) return reason;
  }
  return null;
}
