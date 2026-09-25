/// The machines a machining part can be made on.
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
///  Editing [machines] below is the whole job — nothing else hard-codes a
///  machine anywhere in the app.
/// ─────────────────────────────────────────────────────────────────────────
///
/// Why this exists: a part can run on more than one machine, and supervisors
/// had started encoding that by renaming the part itself ("2214 Fanuc 21",
/// "2214 Fanuc 30"). That works on screen and ruins everything downstream —
/// one part becomes three, and every per-part figure splits with it. The
/// machine belongs beside the part, not inside its name.
library;

class Machine {
  const Machine(this.name, this.number);

  /// The machine family as the floor says it — "Fanuc", "Okuma".
  final String name;

  /// Its number within that family. A string, not an int: these are
  /// identifiers, never arithmetic, and a leading zero would be lost.
  final String number;

  /// "Fanuc 21" — what the picker shows and what lands in the sheet's
  /// Machine column. One field, because that is how the floor says it.
  String get label => '$name $number';
}

const List<Machine> machines = [
  Machine('Fanuc', '20'),
  Machine('Fanuc', '21'),
  Machine('Fanuc', '30'),
  Machine('Okuma', '7'),
  Machine('Okuma', '8'),
  Machine('Okuma', '11'),
];

/// The stored machine matching [label], or null when the sheet holds
/// something the roster no longer lists.
///
/// A row logged against a machine that has since been retired still has to
/// read back, so nothing here ever rejects an unknown value — the picker
/// shows it as-is and lets it be changed.
Machine? machineFromLabel(String? label) {
  final value = (label ?? '').trim();
  if (value.isEmpty) return null;
  for (final machine in machines) {
    if (machine.label.toLowerCase() == value.toLowerCase()) return machine;
  }
  return null;
}
