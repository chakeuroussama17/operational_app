/// One production sheet tab, exactly as the sheet holds it.
///
/// The dashboards aggregate; this does not. It exists so a supervisor can
/// check one specific row — the shift a part actually ran, what the MO was,
/// which hour a rejection landed in — without leaving the app for the
/// spreadsheet.
library;

import '../config/constants.dart';

class RawTable {
  const RawTable({
    required this.tab,
    required this.cols,
    required this.rows,
    required this.total,
  });

  /// The sheet tab's own name, e.g. "Machining_Day".
  final String tab;

  /// Header row, in the sheet's column order.
  final List<String> cols;

  /// Data rows, newest first, each the same length as [cols].
  final List<List<String>> rows;

  /// How many data rows the tab holds in total — [rows] is capped, so this
  /// is what says "showing 300 of 4,812" rather than implying the tab is
  /// small.
  final int total;

  bool get isCapped => rows.length < total;

  factory RawTable.fromJson(Map<String, dynamic> json) {
    final cols = (json['cols'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final rows = (json['rows'] as List? ?? const [])
        .whereType<List>()
        .map((r) => r.map((c) => c?.toString() ?? '').toList())
        .toList();
    return RawTable(
      tab: json['tab']?.toString() ?? '',
      cols: cols,
      rows: rows,
      total: int.tryParse(json['total']?.toString() ?? '') ?? rows.length,
    );
  }
}

/// A tab the Tables screen can open, and the module it belongs to.
///
/// The module matters for access: someone scoped to Casting is shown the
/// casting tabs only. The backend allowlists these names too — this list
/// decides what a given person is *offered*, not what is readable.
class RawTabRef {
  const RawTabRef({
    required this.name,
    required this.label,
    required this.shift,
    required this.module,
  });

  final String name;
  final String label;
  final String shift;
  final String module;

  /// "Casting · Day", or just "Rejections" for the tab that spans both.
  String get title => shift.isEmpty ? label : '$label · $shift';
}

const List<RawTabRef> rawTabRefs = [
  RawTabRef(name: 'Casting_Day', label: 'Casting', shift: 'Day', module: 'casting'),
  RawTabRef(name: 'Casting_Night', label: 'Casting', shift: 'Night', module: 'casting'),
  RawTabRef(name: 'Secondary_Day', label: 'Secondary', shift: 'Day', module: 'secondary'),
  RawTabRef(name: 'Secondary_Night', label: 'Secondary', shift: 'Night', module: 'secondary'),
  RawTabRef(name: 'Machining_Day', label: 'Machining', shift: 'Day', module: 'machining'),
  RawTabRef(name: 'Machining_Night', label: 'Machining', shift: 'Night', module: 'machining'),
  RawTabRef(name: 'Machining_Rejections', label: 'Rejections', shift: '', module: 'machining'),
];

/// The tabs [modules] may open, in the order above. An empty [modules] means
/// no restriction (widget tests, and the admin who sees every department).
List<RawTabRef> rawTabsFor(List<String> modules) {
  if (modules.isEmpty || modules.length >= departments.length) return rawTabRefs;
  return rawTabRefs.where((t) => modules.contains(t.module)).toList();
}
