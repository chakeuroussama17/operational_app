/// How far through its shift a part is, and whether that is on pace.
///
/// A part card used to say "33% logged" — how many boxes were filled, which
/// says nothing about whether the line is keeping up. This carries what the
/// backend knows about the part's row for the shift so the card can answer
/// the question a supervisor actually walks the list to ask: which of these
/// needs me?
library;

enum PaceHealth {
  /// Nothing logged yet, or no plan to judge against. Shown neutrally —
  /// not green, because "no information" is not "fine".
  unknown,

  /// Output at or above the plan's share for the checkpoints logged so far.
  onPace,

  /// Somewhat below it.
  behind,

  /// Well below it.
  wellBehind,

  /// Every checkpoint logged and the plan met.
  complete,
}

class ShiftProgress {
  const ShiftProgress({
    required this.plan,
    required this.actual,
    required this.downtime,
    required this.filled,
    required this.total,
  });

  /// Planned pieces for the shift. Null when none has been set.
  final double? plan;

  /// Everything made so far, across the logged checkpoints.
  final double actual;

  /// Minutes stopped so far. Always 0 outside Machining.
  final double downtime;

  /// Checkpoints logged, out of [total].
  final int filled;
  final int total;

  /// Null when the backend predates these fields, so the card falls back to
  /// its plain "% logged" bar rather than drawing a ring from nothing.
  static ShiftProgress? fromJson(Map<String, dynamic> json) {
    final total = _asInt(json['slotsTotal']);
    if (total == null || total <= 0) return null;
    return ShiftProgress(
      plan: _asDouble(json['plan']),
      actual: _asDouble(json['actual']) ?? 0,
      downtime: _asDouble(json['downtime']) ?? 0,
      filled: _asInt(json['slotsFilled']) ?? 0,
      total: total,
    );
  }

  bool get hasPlan => plan != null && plan! > 0;

  /// Share of the whole shift's plan made so far, 0..1 (capped for drawing;
  /// see [actual] for the real figure, which can exceed the plan).
  double? get planFraction =>
      hasPlan ? (actual / plan!).clamp(0.0, 1.0).toDouble() : null;

  /// Thresholds on output against the plan's share for the checkpoints
  /// logged so far. Five percent of slack before "behind", because counts
  /// are logged at a checkpoint rather than continuously.
  static const double onPaceAt = 0.95;
  static const double behindAt = 0.80;

  PaceHealth get health {
    if (!hasPlan || filled == 0) return PaceHealth.unknown;
    if (filled >= total && actual >= plan! * onPaceAt) {
      return PaceHealth.complete;
    }
    // Judged against what SHOULD be done by now, not against the whole
    // shift: one checkpoint in, a third of the plan is on pace.
    final expected = plan! * filled / total;
    final ratio = expected <= 0 ? 1.0 : actual / expected;
    if (ratio >= onPaceAt) return PaceHealth.onPace;
    if (ratio >= behindAt) return PaceHealth.behind;
    return PaceHealth.wellBehind;
  }

  static int? _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}
