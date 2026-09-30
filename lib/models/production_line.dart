/// The production lines a machining part can be made on.
///
/// ─────────────────────────────────────────────────────────────────────────
///  THE PLANT'S LINE ROSTER. Editing [productionLines] below is the whole
///  job of adding, renaming or retiring a line — nothing else in the app
///  hard-codes one.
///
///  Each entry is a name and a code, in the plant's own order. The name says
///  what the line is ("MACH-2214", "WASHING MACHINE"); the code is unique and
///  is what tells two lines with the same name apart ("M-2214-1" and
///  "M-2214-2"). On screen and on the sheet they are the plant's own
///  WORK CENTER and NAME — the sheet stores them in WorkCenter and Name.
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

  /// What the line is, as the floor says it — "MACH-2214", "CURING".
  /// Not unique: MACH-2214 is three lines.
  final String name;

  /// The line's code — "M-2214-2". Unique, and the thing that tells two lines
  /// sharing a name apart. A string: these are identifiers, never numbers.
  final String number;

  /// "MACH-2214 M-2214-2" — the key the picker uses internally, and what
  /// [splitLineLabel] turns back into the sheet's LineName and LineNo.
  /// Not what a person reads: see [display].
  String get label => '$name $number';

  /// "M-2214-2 · MACH-2214" — code first, because the code is what the floor
  /// picks a line by. The name follows to say what the line is.
  String get display => lineDisplayOf(name, number);
}

const List<ProductionLine> productionLines = [
  ProductionLine('Line 1', '001'),
  ProductionLine('Line 2', '002'),
  ProductionLine('Line 3', '003'),
  ProductionLine('WASHING MACHINE', 'WASHING'),
  ProductionLine('ENGRAVING', 'ENGRAVE'),
  ProductionLine('LASER MARKING', 'LASER.M'),
  ProductionLine('WASHING MACHINE', 'WASH-DRY'),
  ProductionLine('CURING', 'CURING'),
  ProductionLine('MACH-2190', 'M-2190-1'),
  ProductionLine('ASSY-2190', 'A-2190-1'),
  ProductionLine('MACH-2190', 'M-2190-2'),
  ProductionLine('ASSY-2220', 'A-2220-1'),
  ProductionLine('MACH-2073', 'M-2073-1'),
  ProductionLine('MACH-2183', 'A-2183-1'),
  ProductionLine('MACH-2231', 'M-2231-1'),
  ProductionLine('ASSY-2231', 'A-2231-1'),
  ProductionLine('MACH-2232', 'M-2232-1'),
  ProductionLine('ASSY-2232', 'A-2232-1'),
  ProductionLine('MACH-2242', 'M-2242-1'),
  ProductionLine('ASSY-2242', 'A-2242-1'),
  ProductionLine('MACH-2243', 'M-2243-1'),
  ProductionLine('ASSY-2243', 'A-2243-1'),
  ProductionLine('MACH-2224', 'M-2224-1'),
  ProductionLine('ASSY-2224', 'A-2224-1'),
  ProductionLine('MACH-2230', 'M-2230-1'),
  ProductionLine('ASSY-2230', 'A-2230-1'),
  ProductionLine('MACH-2241', 'M-2241-1'),
  ProductionLine('MACH-2236', 'M-2236-1'),
  ProductionLine('ASSY-2236', 'A-2236-1'),
  ProductionLine('MACH-2237', 'M-2237-1'),
  ProductionLine('ASSY-2237', 'A-2237-1'),
  ProductionLine('MACH-2238', 'M-2238-1'),
  ProductionLine('ASSY-2238', 'A-2238-1'),
  ProductionLine('MACH-2245', 'M-2245-1'),
  ProductionLine('ASSY-2245', 'A-2245-1'),
  ProductionLine('MACH-2246', 'M-2246-1'),
  ProductionLine('ASSY-2246', 'A-2246-1'),
  ProductionLine('MACH-2247', 'M-2247-1'),
  ProductionLine('ASSY-2247', 'A-2247-1'),
  ProductionLine('MACH-2248', 'M-2248-1'),
  ProductionLine('ASSY-2248', 'A-2248-1'),
  ProductionLine('MACH-2213', 'M-2213-1'),
  ProductionLine('MACH-2214', 'M-2214-1'),
  ProductionLine('MACH-2214', 'M-2214-2'),
  ProductionLine('MACH-2214', 'M-2214-3'),
  ProductionLine('MACH-2215', 'M-2215-1'),
  ProductionLine('ASSY-2215', 'A-2215-1'),
  ProductionLine('MACH-2216', 'M-2216-1'),
  ProductionLine('ASSY-2216', 'A-2216-1'),
  ProductionLine('MACH-2217', 'M-2217-1'),
  ProductionLine('MACH-2217', 'M-2217-2'),
  ProductionLine('MACH-2218', 'M-2218-1'),
  ProductionLine('MACH-2219', 'M-2219-1'),
  ProductionLine('MACH-2226', 'M-2226-1'),
  ProductionLine('MACH-2228', 'M-2228-1'),
  ProductionLine('MACH-2249', 'M-2249-1'),
  ProductionLine('MACH-2250', 'M-2250-1'),
  ProductionLine('MACH-2234', 'M-2234-1'),
  ProductionLine('MACH-2234', 'M-2234-2'),
  ProductionLine('ASSY-2234', 'A-2234-1'),
  ProductionLine('MACH-2206', 'M-2206-1'),
  ProductionLine('MACH-2206', 'M-2206-2'),
  ProductionLine('MACH-2206', 'M-2206-3'),
  ProductionLine('MACH-2206', 'M-2206-4'),
  ProductionLine('MACH-2206', 'M-2206-5'),
  ProductionLine('LEAK-TEST-2206', 'A-2206-1'),
  ProductionLine('MACH-2251', 'M-2251-1'),
  ProductionLine('MACH-2251', 'M-2251-2'),
  ProductionLine('ASSY-2251', 'A-2251-1'),
  ProductionLine('ASSY-2251', 'A-2251-2'),
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

/// The two stored columns as a person reads them: the code first, then the
/// name — "M-2214-2 · MACH-2214". Either half may be blank on a row that
/// predates the columns, in which case the other stands alone.
String lineDisplayOf(String? name, String? number) {
  final n = (name ?? '').trim();
  final c = (number ?? '').trim();
  if (c.isEmpty) return n;
  if (n.isEmpty) return c;
  return '$c · $n';
}

/// The two stored columns rejoined as the picker's key: "Fanuc" + "21" ->
/// "Fanuc 21". Kept name-first to match [ProductionLine.label].
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
