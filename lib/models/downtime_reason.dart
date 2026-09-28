/// The downtime reasons an operator can pick from.
///
/// THE LIST LIVES ON THE SHEET (the `DowntimeReasons` tab), not here. A super
/// admin adds a reason by adding a row; it reaches every dropdown the next time
/// one opens. Nobody can add one from the app — the picker offers the list and
/// nothing else, because a cause typed in free hand is a cause nobody can add
/// up across a month.
///
/// [bundledDowntimeReasons] is the same fifteen codes the sheet is seeded with.
/// It exists only so the picker still works when the sheet cannot be read — an
/// app installed ahead of the backend deploy, or a bad connection — and is
/// never what a working system shows. The sheet wins whenever it answers.
library;

class DowntimeReason {
  const DowntimeReason(this.code, this.name);

  /// Zero-padded, as the plant writes it ("001", not "1"). May be blank on a
  /// reason a super admin added without one.
  final String code;
  final String name;

  factory DowntimeReason.fromJson(Map<String, dynamic> json) => DowntimeReason(
    (json['code'] ?? '').toString().trim(),
    (json['name'] ?? '').toString().trim(),
  );

  /// "008 · MACHINING MAINTENANCE DOWNTIME" — what the dropdown shows and, for
  /// a chosen reason, exactly what lands in the sheet cell. The code leads so
  /// `LEFT(cell, 3)` pulls it back out for a pivot. The backend builds the
  /// same string, and matches incoming reasons against it.
  String get label => code.isEmpty ? name : '$code · $name';
}

/// Ordered as the plant's own list is: casting causes, then machining, then
/// the scheduled non-production stops.
const List<DowntimeReason> bundledDowntimeReasons = [
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

/// The entry in [reasons] that a stored cell refers to, or null when the cell
/// holds something the list does not — an old free-text reason, or one a super
/// admin has since removed.
///
/// Matches on the whole label without regard to case, then on the bare code,
/// which is how someone editing the sheet by hand would most likely write it.
DowntimeReason? downtimeReasonFromCell(
  String? cell,
  List<DowntimeReason> reasons,
) {
  final value = (cell ?? '').trim();
  if (value.isEmpty) return null;
  for (final reason in reasons) {
    if (reason.label.toLowerCase() == value.toLowerCase()) return reason;
  }
  for (final reason in reasons) {
    if (reason.code.isNotEmpty && reason.code == value) return reason;
  }
  return null;
}
