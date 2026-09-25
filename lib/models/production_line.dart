/// The production lines a machining part can be made on.
///
/// ─────────────────────────────────────────────────────────────────────────
///  PLACEHOLDER ROSTER — REPLACE WITH THE PLANT'S REAL LIST.
///
///  Seeded from names already appearing in the plant's own data: the part
///  renames on the Parts screen ("2214 Fanuc 21") and the downtime notes
///  people typed before the reason codes shipped ("Okuma 7 Atc system
///  condition", "Tool life end okuma 7 & 11"). They are the right shape and
///  probably the right names, but they are not a roster anyone confirmed.
///
///  Editing [productionLines] below is the whole job — nothing else in the
///  app hard-codes a line.
/// ─────────────────────────────────────────────────────────────────────────
///
/// Why this exists: a part can run on more than one line, and supervisors
/// had started encoding that by renaming the part itself ("2214 Fanuc 21",
/// "2214 Fanuc 30"). That works on screen and ruins everything downstream —
/// one part becomes three, and every per-part figure splits with it. The
/// line belongs beside the part, not inside its name.
library;

class ProductionLine {
  const ProductionLine(this.name, this.number);

  /// The line family as the floor says it — "Fanuc", "Okuma".
  final String name;

  /// Its number within that family. A string, not an int: these are
  /// identifiers, never arithmetic, and a leading zero would be lost.
  final String number;

  /// "Fanuc 21" — what the picker shows. The sheet keeps the two halves
  /// apart in LineName and LineNo; this is how the floor says it.
  String get label => '$name $number';
}

const List<ProductionLine> productionLines = [
  ProductionLine('Line 1', '001'),
  ProductionLine('Line 2', '002'),
  ProductionLine('Line 3', '003'),
];

/// Splits a picker label back into the pair the sheet stores.
///
/// A label from the roster splits on its own parts. Anything else — a line
/// since retired, or a value typed straight into the sheet — splits on the
/// last space, which is where the number is if there is one at all. Whatever
/// happens, the name never comes back empty, so a row can always say which
/// line it meant.
({String name, String number}) splitLineLabel(String? label) {
  final value = (label ?? '').trim();
  if (value.isEmpty) return (name: '', number: '');
  final known = lineFromLabel(value);
  if (known != null) return (name: known.name, number: known.number);
  final cut = value.lastIndexOf(' ');
  if (cut <= 0) return (name: value, number: '');
  return (
    name: value.substring(0, cut).trim(),
    number: value.substring(cut + 1).trim(),
  );
}

/// The two stored columns rejoined for display: "Fanuc" + "21" -> "Fanuc 21".
/// Either half may be blank on a row that predates the columns.
String lineLabelOf(String? name, String? number) {
  final parts = [
    (name ?? '').trim(),
    (number ?? '').trim(),
  ]..removeWhere((p) => p.isEmpty);
  return parts.join(' ');
}

/// The stored line matching [label], or null when the sheet holds
/// something the roster no longer lists.
///
/// A row logged against a line that has since been retired still has to
/// read back, so nothing here ever rejects an unknown value — the picker
/// shows it as-is and lets it be changed.
ProductionLine? lineFromLabel(String? label) {
  final value = (label ?? '').trim();
  if (value.isEmpty) return null;
  for (final line in productionLines) {
    if (line.label.toLowerCase() == value.toLowerCase()) return line;
  }
  return null;
}
