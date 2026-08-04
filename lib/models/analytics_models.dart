/// Daily trend totals for one module's Dashboard: output and average LOR%
/// per day over a window (default 14 days), plus rejection totals for
/// Machining. Days with no data are zero/null-filled by the backend so the
/// chart always shows a full date axis.
///
/// Alongside the day-by-day series, the same window is sliced several more
/// ways, each answering a question a supervisor actually asks:
///   [byGroup]          who's behind — DCM / Station / Customer
///   [parts]            what are we running, and (Machining) what's scrapping
///   [byShift]          does Day or Night produce more
///   [shiftSeries]      ...and is the gap widening
///   [groupSeries]      one machine's own trend, without a second request
///   [rejectionsByType] what's failing (Machining only)
library;

class AnalyticsSeries {
  const AnalyticsSeries({
    required this.dates,
    required this.output,
    required this.lorPercent,
    this.rejection = const [],
    this.byGroup = const [],
    this.rejectionsByType = const [],
    this.parts = const [],
    this.byShift = const [],
    this.shiftSeries = const {},
    this.groupSeries = const {},
    this.groupLorSeries = const {},
  });

  final List<String> dates; // "yyyy-MM-dd", oldest first
  final List<double> output;
  final List<double?> lorPercent; // null on days with no logged LOR
  final List<double> rejection; // empty for Casting/Secondary

  /// Output + avg LOR% totalled per DCM/Station/Customer over the window,
  /// sorted highest output first.
  final List<GroupTotal> byGroup;

  /// Defect quantity totalled per rejection type over the window, sorted
  /// highest first. Empty for Casting/Secondary.
  final List<TypeTotal> rejectionsByType;

  /// One entry per (group, part). Flat and carrying its group, so the same
  /// list answers "which part runs most" (summed across groups) and "for
  /// this machine, which part runs most" (filtered) — see [partsFor].
  final List<PartTotal> parts;

  /// Day vs Night totals for the window.
  final List<ShiftTotal> byShift;

  /// Daily output per shift, keyed "Day"/"Night".
  final Map<String, List<double>> shiftSeries;

  /// Daily output per group, so a machine filter redraws without refetching.
  final Map<String, List<double>> groupSeries;

  /// Daily avg LOR% per group; null entries are days that group didn't run.
  final Map<String, List<double?>> groupLorSeries;

  /// Every group that reported in this window, in the ranking's order
  /// (highest output first) — what the filter chips offer.
  List<String> get groupNames => [for (final g in byGroup) g.group];

  /// Parts for one group, or every part totalled across groups when [group]
  /// is null. Always sorted highest output first.
  List<PartTotal> partsFor(String? group) {
    if (group != null) {
      return [
        for (final p in parts)
          if (p.group == group) p,
      ]..sort((a, b) => b.output.compareTo(a.output));
    }
    final merged = <String, PartTotal>{};
    for (final p in parts) {
      final existing = merged[p.part];
      merged[p.part] = existing == null
          ? p
          : PartTotal(
              // Once a part spans more than one machine, naming just one of
              // them would be wrong — groupCount carries the fact instead.
              group: p.group == existing.group ? p.group : '',
              groupCount: existing.groupCount + 1,
              part: p.part,
              name: p.name.isNotEmpty ? p.name : existing.name,
              output: existing.output + p.output,
              rejection: existing.rejection + p.rejection,
              // A part's LOR across machines is only meaningful per machine,
              // so the merged row deliberately drops it rather than
              // inventing an average of averages.
              lorPercent: null,
            );
    }
    return merged.values.toList()..sort((a, b) => b.output.compareTo(a.output));
  }

  factory AnalyticsSeries.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;

    Map<String, List<double>> numberSeries(dynamic raw) {
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries)
          entry.key.toString(): (entry.value as List? ?? const [])
              .map(toDouble)
              .toList(),
      };
    }

    return AnalyticsSeries(
      dates: (json['dates'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      output: (json['output'] as List? ?? const []).map(toDouble).toList(),
      lorPercent: (json['lorPercent'] as List? ?? const [])
          .map((e) => e == null ? null : (e as num).toDouble())
          .toList(),
      rejection: (json['rejection'] as List? ?? const [])
          .map(toDouble)
          .toList(),
      byGroup: (json['byGroup'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => GroupTotal.fromJson(m.cast<String, dynamic>()))
          .toList(),
      rejectionsByType: (json['rejectionsByType'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => TypeTotal.fromJson(m.cast<String, dynamic>()))
          .toList(),
      parts: (json['parts'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => PartTotal.fromJson(m.cast<String, dynamic>()))
          .toList(),
      byShift: (json['byShift'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => ShiftTotal.fromJson(m.cast<String, dynamic>()))
          .toList(),
      shiftSeries: numberSeries(json['shiftSeries']),
      groupSeries: numberSeries(json['groupSeries']),
      groupLorSeries: (json['groupLorSeries'] is! Map)
          ? const {}
          : {
              for (final entry in (json['groupLorSeries'] as Map).entries)
                entry.key.toString(): (entry.value as List? ?? const [])
                    .map((e) => e == null ? null : (e as num).toDouble())
                    .toList(),
            },
    );
  }
}

/// One DCM/Station/Customer's totals for the window — a row of the "who's
/// behind" ranking bar chart.
class GroupTotal {
  const GroupTotal({
    required this.group,
    required this.output,
    this.lorPercent,
  });

  final String group;
  final double output;
  final double? lorPercent;

  factory GroupTotal.fromJson(Map<String, dynamic> json) => GroupTotal(
    group: (json['group'] ?? '').toString(),
    output: (json['output'] as num?)?.toDouble() ?? 0,
    lorPercent: (json['lorPercent'] as num?)?.toDouble(),
  );
}

/// One defect type's total for the window — a row of the rejection
/// breakdown (donut + ranked list).
class TypeTotal {
  const TypeTotal({required this.type, required this.qty});

  final String type;
  final double qty;

  factory TypeTotal.fromJson(Map<String, dynamic> json) => TypeTotal(
    type: (json['type'] ?? '').toString(),
    qty: (json['qty'] as num?)?.toDouble() ?? 0,
  );
}

/// One part's totals for the window, within one group. [group] is empty on a
/// row merged across groups by [AnalyticsSeries.partsFor].
class PartTotal {
  const PartTotal({
    required this.group,
    required this.part,
    required this.name,
    required this.output,
    this.lorPercent,
    this.rejection = 0,
    this.groupCount = 1,
  });

  /// Empty once merged across more than one group — see [groupCount].
  final String group;

  /// How many machines/stations/customers this row covers. 1 unless
  /// [AnalyticsSeries.partsFor] merged it.
  final int groupCount;
  final String part;

  /// Human-readable part name snapshotted onto the row; often blank on older
  /// rows, so callers fall back to [part].
  final String name;
  final double output;
  final double? lorPercent;

  /// Machining only — 0 elsewhere.
  final double rejection;

  /// Share of everything this part produced that was scrapped. Null when the
  /// part has no activity at all. Output counts GOOD parts, so the
  /// denominator is output + rejections, not output alone.
  double? get rejectRate {
    final total = output + rejection;
    if (total <= 0) return null;
    return rejection / total * 100;
  }

  /// "A1 · ARM-LH" when a name is known, else just the code.
  String get label => name.isEmpty || name == part ? part : '$part · $name';

  /// What to show in a "which machine" column. A part that ran on several
  /// says so rather than leaving a blank cell, which reads as missing data.
  String groupLabelWith(String groupNoun) =>
      groupCount > 1 ? '$groupCount ${groupNoun}s' : group;

  factory PartTotal.fromJson(Map<String, dynamic> json) => PartTotal(
    group: (json['group'] ?? '').toString(),
    part: (json['part'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    output: (json['output'] as num?)?.toDouble() ?? 0,
    lorPercent: (json['lorPercent'] as num?)?.toDouble(),
    rejection: (json['rejection'] as num?)?.toDouble() ?? 0,
  );
}

/// Day or Night totals for the window.
class ShiftTotal {
  const ShiftTotal({
    required this.shift,
    required this.output,
    this.lorPercent,
  });

  final String shift;
  final double output;
  final double? lorPercent;

  factory ShiftTotal.fromJson(Map<String, dynamic> json) => ShiftTotal(
    shift: (json['shift'] ?? '').toString(),
    output: (json['output'] as num?)?.toDouble() ?? 0,
    lorPercent: (json['lorPercent'] as num?)?.toDouble(),
  );
}
