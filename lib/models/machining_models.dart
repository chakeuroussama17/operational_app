/// Data types for the Machining module's incremental logging API.
///
/// One level deeper than Casting/Secondary: Operation -> Customer -> Part ->
/// entry (keyed by Customer + PartNo + Operation + shift-date). Shift-aware
/// like the others (Day 10AM-8PM / Night 10PM-8AM crossing midnight), MO number
/// per part.
///
/// Rejections are NOT per slot — they're a typed list for the whole entry
/// ("5 POROSITY, 2 COLD SHUT"), posted as `Rejections` and stored in their own
/// sheet. See [RejectionEntry] in models/rejection.dart.
library;

import 'machine.dart';
import 'part_code.dart';
import 'rejection.dart';

/// One checkpoint of a shift — three of them, one every four hours.
class MachiningSlot {
  const MachiningSlot(this.label, this.outputKey, this.lorKey);

  final String label;

  /// Column/field name of the user-entered count, e.g. "Actual_10AM".
  /// This is EVERY part the hour produced, good and scrap together.
  final String outputKey;

  /// Column/field name of the backend-computed LOR%, e.g. "LOR_10AM".
  final String lorKey;

  /// The bare hour ("10AM") — how the sheet tags a rejection and a LogMeta
  /// entry to its slot.
  String get slotKey => outputKey.replaceFirst('Actual_', '');

  /// Column/field name of the hour's downtime in minutes, e.g.
  /// "Downtime_10AM". Derived from [slotKey] rather than stored, so a slot
  /// can never be declared with the two out of step.
  String get downtimeKey => 'Downtime_$slotKey';

  /// Column/field name of the free-text reason for that stop, e.g.
  /// "DowntimeReason_12PM". Minutes say how long; only this says why.
  String get downtimeReasonKey => 'DowntimeReason_$slotKey';
}

/// Day shift: 10AM-8PM, logged every 4 hours.
const List<MachiningSlot> machiningDaySlots = [
  MachiningSlot('12 PM', 'Actual_12PM', 'LOR_12PM'),
  MachiningSlot('4 PM', 'Actual_4PM', 'LOR_4PM'),
  MachiningSlot('7:30 PM', 'Actual_7_30PM', 'LOR_7_30PM'),
];

/// Night shift: 10PM-8AM, logged every 4 hours.
const List<MachiningSlot> machiningNightSlots = [
  MachiningSlot('12 AM', 'Actual_12AM', 'LOR_12AM'),
  MachiningSlot('4 AM', 'Actual_4AM', 'LOR_4AM'),
  MachiningSlot('7:30 AM', 'Actual_7_30AM', 'LOR_7_30AM'),
];

List<MachiningSlot> machiningSlotsForShift(String shift) =>
    shift == 'Night' ? machiningNightSlots : machiningDaySlots;

/// Day runs from 10:00 through 21:59; Night takes over at 22:00.
String autoDetectMachiningShift() {
  final hour = DateTime.now().hour;
  return (hour >= 10 && hour < 22) ? 'Day' : 'Night';
}

/// Which operation a log belongs to — the first thing the module asks for,
/// ahead of the customer. The plant runs exactly two, so they ship with the
/// app rather than being configured; [value] is what lands in the sheet's
/// Operation column and must stay lowercase to match the rows already there.
class MachiningOperation {
  const MachiningOperation({
    required this.value,
    required this.label,
    required this.description,
  });

  final String value;
  final String label;
  final String description;
}

/// Named so they can be used where a compile-time constant is required —
/// `machiningOperations.first` is not one, since indexing a const list isn't
/// itself a constant expression.
const MachiningOperation machiningOperation = MachiningOperation(
  value: 'machining',
  label: 'Machining',
  description: 'CNC and machining lines',
);

const MachiningOperation assemblyOperation = MachiningOperation(
  value: 'assembly',
  label: 'Assembly',
  description: 'Assembly and fitting lines',
);

const List<MachiningOperation> machiningOperations = [
  machiningOperation,
  assemblyOperation,
];

/// Display name for a stored Operation value, falling back to the raw value so
/// a row logged under an operation that has since been retired still reads.
String machiningOperationLabel(String value) {
  for (final operation in machiningOperations) {
    if (operation.value == value) return operation.label;
  }
  return value;
}

/// The part-master entries belonging to [operation].
///
/// The plant names its machining parts by what happens to them: every entry
/// ends in `-MACH` or `-ASSY` (`2244-MAR-NO2-BRKT-ENGINE-LH-MACH`), so the
/// suffix IS the operation and the add-part picker shows one half of the list
/// instead of all of it.
///
/// A handful of names describe the step rather than the operation
/// (`2230-PR2-BRKT-OIL-FILTER-LEAKTEST`). Those fall back to the barcode's own
/// `-M`/`-A` suffix, which the master carries on every row — without it such a
/// part would match neither operation and become impossible to add at all.
List<PartCode> partCodesForOperation(
  List<PartCode> codes,
  MachiningOperation operation,
) {
  return codes
      .where((code) => _operationOf(code) == operation.value)
      .toList(growable: false);
}

/// Which operation a master entry belongs to, or null when nothing identifies
/// it — an unclassifiable part is left out of both lists rather than guessed
/// into one.
String? _operationOf(PartCode code) {
  final name = (code.name ?? '').trim().toUpperCase();
  if (name.endsWith('MACH')) return 'machining';
  if (name.endsWith('ASSY')) return 'assembly';

  final barcode = (code.barcode ?? '').trim().toUpperCase();
  if (barcode.endsWith('-M')) return 'machining';
  if (barcode.endsWith('-A')) return 'assembly';
  return null;
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
/// (manufacturing order) number and this shift's completion level. Since the
/// Line step was removed, this is the level that opens the entry form — hence
/// the fill percentage.
class MachiningPartStatus {
  const MachiningPartStatus({
    required this.part,
    this.mo,
    this.name,
    this.machineName = '',
    this.machineNo = '',
    this.lastUpdated,
    this.fillPercent = 0,
  });

  /// The part CODE (chosen from the master list) — this card's title.
  final String part;
  final String? mo;

  /// Which machine this entry runs on, as the sheet keeps it: name and
  /// number in their own columns. Part of the entry's identity, so two cards
  /// can share a part code and differ only here. Both empty on rows
  /// configured before the machine was asked for.
  final String machineName;
  final String machineNo;

  /// "Fanuc 21" — the pair as the picker and the cards show it.
  String get machine => machineLabelOf(machineName, machineNo);

  /// Human-readable part name from the master list.
  final String? name;
  final String? lastUpdated;

  /// 0-100: how many of the three checkpoints are filled this shift.
  final int fillPercent;

  factory MachiningPartStatus.fromJson(Map<String, dynamic> json) {
    final fill = num.tryParse(json['fillPercent']?.toString() ?? '') ?? 0;
    return MachiningPartStatus(
      part: cleanCell(json['part']) ?? '',
      mo: cleanCell(json['mo']),
      name: cleanCell(json['name']),
      machineName: cleanCell(json['machineName']) ?? '',
      machineNo: cleanCell(json['machineNo']) ?? '',
      lastUpdated: cleanCell(json['lastUpdated']),
      fillPercent: fill.clamp(0, 100).round(),
    );
  }
}

/// Today's saved row for a Customer + Part + Operation. Field access is by
/// column name so the row survives backend column additions untouched.
class MachiningRow {
  const MachiningRow(this.raw);

  final Map<String, dynamic> raw;

  /// Cell as a display/edit string, or null when empty. "300.0" -> "300".
  String? value(String key) => cleanCell(raw[key]);

  /// This entry's defect list, sent alongside the row. Empty when none were
  /// logged (or when an older backend didn't send the field).
  List<RejectionEntry> get rejections {
    final raw = this.raw['Rejections'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => RejectionEntry.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// LOR cell formatted for the read-only badge, e.g. "83.33%".
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
    return formatLor(n * 100);
  }
}

/// A percentage as the LOR badge shows it: at most two decimals, and only
/// where they carry information ("50%", "37.5%", "83.33%").
String formatLor(num percent) {
  final label = percent.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$label%';
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
