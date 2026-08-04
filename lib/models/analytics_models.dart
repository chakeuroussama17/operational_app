/// Daily trend totals for one module's Dashboard: output and average LOR%
/// per day over a window (default 14 days), plus rejection totals for
/// Machining. Days with no data are zero/null-filled by the backend so the
/// chart always shows a full date axis.
///
/// Alongside the day-by-day series, the same window is sliced two more ways:
/// [byGroup] (who's behind — DCM/Station/Customer) and, for Machining only,
/// [rejectionsByType] (what's actually failing).
library;

class AnalyticsSeries {
  const AnalyticsSeries({
    required this.dates,
    required this.output,
    required this.lorPercent,
    this.rejection = const [],
    this.byGroup = const [],
    this.rejectionsByType = const [],
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

  factory AnalyticsSeries.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;

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
