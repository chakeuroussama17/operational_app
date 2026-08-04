import 'package:flutter/material.dart';

import '../config/constants.dart';

/// One row: a magnitude with the identity it belongs to.
class RankedBarEntry {
  const RankedBarEntry({
    required this.label,
    required this.value,
    this.sublabel,
  });

  final String label;
  final double value;

  /// Optional small second line under the label (e.g. an LOR% alongside an
  /// output total).
  final String? sublabel;
}

/// Horizontal ranking bar chart — "compare magnitude" is a sequential/
/// single-hue job, and every bar here is the SAME series (one metric, sliced
/// by DCM/Station/Customer or by defect type), so every bar takes the one
/// color: never a rainbow per row. Sorted by the order entries arrive in
/// (the caller sorts; this never re-sorts, so it never "recolors on filter").
class RankedBarChart extends StatelessWidget {
  const RankedBarChart({
    super.key,
    required this.title,
    required this.entries,
    required this.color,
    this.suffix = '',
    this.emptyMessage = 'No data logged yet in this window',
    this.colorForIndex,
  });

  final String title;
  final List<RankedBarEntry> entries;
  final Color color;
  final String suffix;
  final String emptyMessage;

  /// When set, overrides [color] per row — used for the rejection-type chart,
  /// which shares its identity colors with the companion donut so the same
  /// defect reads as the same hue in both.
  final Color Function(int index)? colorForIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            _Bars(
              entries: entries,
              color: color,
              suffix: suffix,
              colorForIndex: colorForIndex,
            ),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.entries,
    required this.color,
    required this.suffix,
    required this.colorForIndex,
  });

  final List<RankedBarEntry> entries;
  final Color color;
  final String suffix;
  final Color Function(int index)? colorForIndex;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final maxV = entries
        .map((e) => e.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1.0 : maxV;

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _BarRow(
            entry: entries[i],
            fraction: (entries[i].value / safeMax).clamp(0, 1),
            color: colorForIndex?.call(i) ?? color,
            valueLabel: '${_fmt(entries[i].value)}$suffix',
          ),
        ],
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.entry,
    required this.fraction,
    required this.color,
    required this.valueLabel,
  });

  final RankedBarEntry entry;
  final double fraction;
  final Color color;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (entry.sublabel != null)
                Text(
                  entry.sublabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // ≤24px thick, 4px rounded data-end, square at the baseline —
              // grown from a single left baseline, never filling the track.
              return SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
