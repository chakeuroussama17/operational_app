/// Daily trend totals for one module's Dashboard chart: output and average
/// LOR% per day over a window (default 14 days), plus rejection totals for
/// Machining. Days with no data are zero/null-filled by the backend so the
/// chart always shows a full date axis.
library;

class AnalyticsSeries {
  const AnalyticsSeries({
    required this.dates,
    required this.output,
    required this.lorPercent,
    this.rejection = const [],
  });

  final List<String> dates; // "yyyy-MM-dd", oldest first
  final List<double> output;
  final List<double?> lorPercent; // null on days with no logged LOR
  final List<double> rejection; // empty for Casting/Secondary

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
    );
  }
}
