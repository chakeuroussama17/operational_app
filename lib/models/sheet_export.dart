/// Turning a sheet tab into a file someone can send.
///
/// Kept apart from the screen so the two things most likely to be wrong —
/// which rows a date range actually catches, and whether a value with a
/// comma in it survives the round trip — can be tested without a widget.
library;

import 'raw_table.dart';

/// The ranges the download offers.
enum ExportRange { today, month, custom }

/// A resolved window, inclusive at both ends.
class DateWindow {
  const DateWindow(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// [now] is injectable so the tests aren't hostage to the calendar.
  factory DateWindow.forRange(ExportRange range, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (range) {
      case ExportRange.today:
        return DateWindow(today, today);
      case ExportRange.month:
        return DateWindow(
          DateTime(now.year, now.month, 1),
          // Day 0 of next month is the last day of this one, which handles
          // February and the 30/31 split without a table of lengths.
          DateTime(now.year, now.month + 1, 0),
        );
      case ExportRange.custom:
        return DateWindow(today, today);
    }
  }

  bool contains(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  bool get isSingleDay =>
      from.year == to.year && from.month == to.month && from.day == to.day;

  String get label => isSingleDay
      ? _iso(from)
      : '${_iso(from)}_to_${_iso(to)}';

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// The sheet's Date column, whatever it is called or formatted as.
///
/// The backend hands back DISPLAY values, so this is the text an operator
/// would see in the cell — usually yyyy-mm-dd, but a tab whose format was
/// changed by hand can read dd/mm/yyyy instead.
DateTime? parseSheetDate(String value) {
  final s = value.trim();
  if (s.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }

  // dd/mm/yyyy — day first, which is how this plant writes dates. A
  // yyyy-first value has already been caught above, so there is no
  // ambiguity left to guess at.
  final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
  if (slash != null) {
    return DateTime(
      int.parse(slash.group(3)!),
      int.parse(slash.group(2)!),
      int.parse(slash.group(1)!),
    );
  }
  return null;
}

/// Index of the column holding the row's date, or -1 when the tab has none.
int dateColumnIndex(List<String> cols) =>
    cols.indexWhere((c) => c.trim().toLowerCase() == 'date');

/// The rows of [table] whose date falls inside [window].
///
/// A row whose date cannot be read is LEFT OUT rather than let through: a
/// download labelled "August" that quietly carries an undated row is worse
/// than one that is short.
List<List<String>> rowsInWindow(RawTable table, DateWindow window) {
  final dateCol = dateColumnIndex(table.cols);
  if (dateCol < 0) return const [];
  return table.rows.where((row) {
    if (dateCol >= row.length) return false;
    final d = parseSheetDate(row[dateCol]);
    return d != null && window.contains(d);
  }).toList();
}

/// RFC 4180 CSV. Excel and Sheets both read this; the quoting is what stops
/// a part name containing a comma from becoming two columns.
String toCsv(List<String> cols, List<List<String>> rows) {
  final buffer = StringBuffer()..writeln(cols.map(_field).join(','));
  for (final row in rows) {
    buffer.writeln([
      for (var i = 0; i < cols.length; i++)
        _field(i < row.length ? row[i] : ''),
    ].join(','));
  }
  return buffer.toString();
}

String _field(String value) {
  final needsQuoting =
      value.contains(',') || value.contains('"') || value.contains('\n');
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// e.g. "Machining_Day_2026-08-17.csv".
String exportFileName(String tab, DateWindow window) =>
    '${tab}_${window.label}.csv';
