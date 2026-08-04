import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/constants.dart';

class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

/// Part-to-whole, at a glance only — never for comparing two close values (a
/// bar does that; see [RankedBarChart] for the precise ranking of the same
/// data). Capped at 6 segments; a caller with more should fold the tail into
/// an "Other" slice before handing it here. The legend is not decoration —
/// for ≥2 series it is the dependable identity channel, not just color.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.title,
    required this.slices,
    required this.totalLabel,
    this.emptyMessage = 'No data logged yet in this window',
  });

  final String title;
  final List<DonutSlice> slices;
  final String totalLabel;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);

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
          const SizedBox(height: 14),
          if (slices.isEmpty || total <= 0)
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
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 340;
                final ring = _Ring(
                  slices: slices,
                  total: total,
                  totalLabel: totalLabel,
                  surfaceColor: AppColors.surface,
                );
                final legend = _Legend(slices: slices, total: total);
                if (narrow) {
                  return Column(
                    children: [
                      Center(child: ring),
                      const SizedBox(height: 16),
                      legend,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ring,
                    const SizedBox(width: 20),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.slices,
    required this.total,
    required this.totalLabel,
    required this.surfaceColor,
  });

  final List<DonutSlice> slices;
  final double total;
  final String totalLabel;
  final Color surfaceColor;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(148, 148),
            painter: _DonutPainter(
              slices: slices,
              total: total,
              surfaceColor: surfaceColor,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(total),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                totalLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.surfaceColor,
  });

  final List<DonutSlice> slices;
  final double total;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 26.0;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // A ~2° surface-color gap between slices does the separating — no
    // stroke drawn around each segment.
    const gapRadians = 0.035;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * 2 * math.pi;
      final drawSweep = (sweep - gapRadians).clamp(0.0, sweep);
      canvas.drawArc(
        arcRect,
        start + gapRadians / 2,
        drawSweep,
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.total != total;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.slices, required this.total});

  final List<DonutSlice> slices;
  final double total;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_fmt(slice.value)} · ${(slice.value / total * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
