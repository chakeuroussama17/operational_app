/// One entry from the rejection-codes master (imported CSV).
///
/// A few names repeat under different codes (FOLDED is both 153 and 179), so
/// [code] is part of the identity, not decoration.
class RejectionType {
  const RejectionType({required this.code, required this.type});

  final String code;
  final String type;

  factory RejectionType.fromJson(Map<String, dynamic> json) => RejectionType(
    code: (json['code'] ?? '').toString().trim(),
    type: (json['type'] ?? '').toString().trim(),
  );

  /// "064 · POROSITY" — what the picker rows and the chosen field show.
  String get label => code.isEmpty ? type : '$code · $type';
}

/// One editable "N of this defect" line on the Machining entry screen.
///
/// Mutable because the screen edits these in place as rows are added, typed
/// into and removed; the whole list is posted on submit and replaces whatever
/// the sheet held for that entry.
class RejectionEntry {
  RejectionEntry({
    this.qty = '',
    this.code = '',
    this.type = '',
    this.slot = '',
  });

  factory RejectionEntry.fromJson(Map<String, dynamic> json) => RejectionEntry(
    qty: (json['qty'] ?? '').toString().trim(),
    code: (json['code'] ?? '').toString().trim(),
    type: (json['type'] ?? '').toString().trim(),
    slot: (json['slot'] ?? '').toString().trim(),
  );

  String qty;
  String code;
  String type;

  /// Which hour this defect belongs to ("8AM"). Empty on rows written before
  /// the sheet tracked the hour — those stay in the sheet untouched.
  String slot;

  /// A row the user started but didn't finish is dropped rather than posted.
  bool get isComplete => qty.trim().isNotEmpty && type.trim().isNotEmpty;

  /// "064 · POROSITY" — what the chosen-type field shows.
  String get label => code.isEmpty ? type : '$code · $type';

  Map<String, String> toJson() => {
    'qty': qty.trim(),
    'code': code,
    'type': type,
    'slot': slot,
  };
}
