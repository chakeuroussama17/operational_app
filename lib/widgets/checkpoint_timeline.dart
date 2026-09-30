import 'dart:async';

import 'package:flutter/material.dart';

import '../config/constants.dart';

/// One checkpoint on the strip.
class TimelineCheckpoint {
  const TimelineCheckpoint({
    required this.label,
    required this.slotKey,
    required this.logged,
  });

  /// "7:30 PM" — as the form labels it.
  final String label;

  /// "7_30PM" — the stored key, which is also where the clock time comes from.
  final String slotKey;

  /// Already on the sheet.
  final bool logged;
}

enum CheckpointState { done, due, overdue, upcoming, idle }

/// The clock time a checkpoint key stands for: "7_30PM" -> 19:30.
/// Null for a key that is not a clock time, so an unexpected slot shows as a
/// plain step rather than breaking the strip.
({int hour, int minute})? checkpointClock(String slotKey) {
  final match = RegExp(r'^(\d{1,2})(?:_(\d{2}))?(AM|PM)$').firstMatch(slotKey);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2) ?? '0');
  final pm = match.group(3) == 'PM';
  if (hour == 12) hour = 0;
  if (pm) hour += 12;
  return (hour: hour, minute: minute);
}

/// Which shift the wall clock is in: Day 10:00-21:59, Night otherwise.
String currentShiftAt(DateTime now) =>
    (now.hour >= 10 && now.hour < 22) ? 'Day' : 'Night';

/// When [slotKey] falls in the shift instance running at [now]. Night's
/// checkpoints are all after midnight, so they belong to tomorrow while the
/// shift is still in its evening and to today once midnight has passed.
DateTime? checkpointTime(String slotKey, String shift, DateTime now) {
  final clock = checkpointClock(slotKey);
  if (clock == null) return null;
  var day = DateTime(now.year, now.month, now.day);
  if (shift == 'Night' && now.hour >= 22) {
    day = day.add(const Duration(days: 1));
  }
  return day.add(Duration(hours: clock.hour, minutes: clock.minute));
}

/// How long after its time a checkpoint still counts as "due" rather than
/// "overdue" — counts are logged around the hour, not on the second.
const Duration checkpointGrace = Duration(minutes: 30);

/// Each checkpoint's state at [now]. Clock-based states only apply while
/// [shift] is the one running; a supervisor looking at the other shift sees
/// what is logged and nothing about deadlines that are not theirs.
List<CheckpointState> checkpointStates(
  List<TimelineCheckpoint> checkpoints,
  String shift,
  DateTime now,
) {
  final live = currentShiftAt(now) == shift;
  var dueTaken = false;
  return [
    for (final c in checkpoints)
      () {
        if (c.logged) return CheckpointState.done;
        if (!live) return CheckpointState.idle;
        final at = checkpointTime(c.slotKey, shift, now);
        if (at == null) return CheckpointState.upcoming;
        if (now.isAfter(at.add(checkpointGrace))) {
          return CheckpointState.overdue;
        }
        if (!dueTaken) {
          dueTaken = true;
          return CheckpointState.due;
        }
        return CheckpointState.upcoming;
      }(),
  ];
}

/// "in 1h 20m" / "due now" — how the due checkpoint is described.
String dueText(DateTime at, DateTime now) {
  if (!now.isBefore(at)) return 'due now';
  final left = at.difference(now);
  final h = left.inHours;
  final m = left.inMinutes.remainder(60);
  if (h == 0) return 'in ${m}m';
  return m == 0 ? 'in ${h}h' : 'in ${h}h ${m}m';
}

/// The shift's checkpoints as a strip across the top of the entry form:
/// what is logged, what is due and when, and what was missed.
///
/// The four-hour rhythm is the whole shape of the app, and before this it was
/// only implied by three cards in a column. The strip says "what should I be
/// doing now" at a glance, and keeps saying it — it re-reads the clock every
/// half minute.
class CheckpointTimeline extends StatefulWidget {
  const CheckpointTimeline({
    super.key,
    required this.shift,
    required this.checkpoints,
    this.clock,
  });

  final String shift;
  final List<TimelineCheckpoint> checkpoints;

  /// Test seam. Production reads the wall clock.
  final DateTime Function()? clock;

  @override
  State<CheckpointTimeline> createState() => _CheckpointTimelineState();
}

class _CheckpointTimelineState extends State<CheckpointTimeline>
    with SingleTickerProviderStateMixin {
  Timer? _tick;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      _pulseIfDue();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pulseIfDue());
  }

  /// A short burst — three pulses — when a checkpoint is due, repeated on each
  /// half-minute tick. A pulse that never stops is noise after the first
  /// minute on the floor, and it would also never let a test settle.
  void _pulseIfDue() {
    if (!mounted || _pulse.isAnimating) return;
    final due = checkpointStates(
      widget.checkpoints,
      widget.shift,
      _now,
    ).contains(CheckpointState.due);
    if (due) _pulse.repeat(reverse: true, count: 3);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final states = checkpointStates(widget.checkpoints, widget.shift, now);

    final nodes = <Widget>[];
    for (var i = 0; i < widget.checkpoints.length; i++) {
      final c = widget.checkpoints[i];
      final state = states[i];
      if (i > 0) {
        final prevDone = states[i - 1] == CheckpointState.done;
        nodes.add(
          Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.only(bottom: 30),
              decoration: BoxDecoration(
                color: prevDone ? AppColors.success : AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }
      final at = checkpointTime(c.slotKey, widget.shift, now);
      final caption = switch (state) {
        CheckpointState.done => 'logged',
        CheckpointState.due => at == null ? 'due' : dueText(at, now),
        CheckpointState.overdue => 'overdue',
        CheckpointState.upcoming || CheckpointState.idle => '',
      };
      nodes.add(
        _Node(label: c.label, caption: caption, state: state, pulse: _pulse),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: nodes,
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.label,
    required this.caption,
    required this.state,
    required this.pulse,
  });

  final String label;
  final String caption;
  final CheckpointState state;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    const size = 30.0;
    final Widget dot = switch (state) {
      CheckpointState.done => _filled(
        AppColors.success,
        const Icon(Icons.check_rounded, size: 18, color: Colors.white),
      ),
      CheckpointState.overdue => _filled(
        AppColors.danger,
        const Icon(Icons.priority_high_rounded, size: 17, color: Colors.white),
      ),
      CheckpointState.due => AnimatedBuilder(
        animation: pulse,
        builder: (context, child) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.authGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.authPink.withValues(
                  alpha: 0.25 + 0.35 * pulse.value,
                ),
                blurRadius: 6 + 10 * pulse.value,
                spreadRadius: 1 + 3 * pulse.value,
              ),
            ],
          ),
          child: child,
        ),
        child: const Icon(
          Icons.schedule_rounded,
          size: 16,
          color: Colors.white,
        ),
      ),
      CheckpointState.upcoming || CheckpointState.idle => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderSubtle, width: 2),
          color: AppColors.surfaceTint,
        ),
      ),
    };
    final captionColor = switch (state) {
      CheckpointState.done => AppColors.success,
      CheckpointState.overdue => AppColors.danger,
      CheckpointState.due => AppColors.authPink,
      _ => AppColors.textSecondary,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: state == CheckpointState.due
                ? FontWeight.w800
                : FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(
          height: 15,
          child: Text(
            caption,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: captionColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _filled(Color color, Widget icon) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: icon,
  );
}
