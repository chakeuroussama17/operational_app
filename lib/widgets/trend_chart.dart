import 'package:flutter/material.dart';

import '../config/constants.dart';

/// Small line-chart card for one metric over time (e.g. daily output, or
/// LOR%). Null entries (no data logged that day) leave a gap in the line
/// rather than dropping to zero.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.title,
    required this.dates,
    required this.values,
    required this.color,
    this.suffix = '',
  });

  final String title;
  final List<String> dates;
  final List<double?> values;
  final Color color;

  /// Appended to the latest-value badge and axis labels, e.g. "%".
  final String suffix;

  bool get _hasData => values.any((v) => v != null && v != 0);

  @override
  Widget build(BuildContext context) {
    final latest = values.isNotEmpty ? values.last : null;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (latest != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Today: ${_formatValue(latest)}$suffix',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: _hasData
                ? CustomPaint(
                    size: Size.infinite,
                    painter: _LineChartPainter(values: values, color: color),
                  )
                : Center(
                    child: Text(
                      'No data logged yet in this window',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
          ),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_shortDate(dates.first), style: _axisStyle),
                Text(_shortDate(dates.last), style: _axisStyle),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static TextStyle get _axisStyle => TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w600,
  );

  String _formatValue(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _shortDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    return '${parts[1]}/${parts[2]}';
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.values, required this.color});

  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final nonNull = values.whereType<double>();
    final maxV = nonNull.isEmpty
        ? 1.0
        : nonNull.reduce((a, b) => a > b ? a : b);
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;

    // Gridlines.
    final gridPaint = Paint()
      ..color = AppColors.borderSubtle
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;
    Offset? pointAt(int i) {
      final v = values[i];
      if (v == null) return null;
      final x = stepX * i;
      final y = size.height - (v / top) * size.height;
      return Offset(x, y.clamp(0, size.height));
    }

    // Build contiguous segments, skipping gaps at null values.
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path? segment;
    final segments = <Path>[];
    for (var i = 0; i < values.length; i++) {
      final p = pointAt(i);
      if (p == null) {
        segment = null;
        continue;
      }
      if (segment == null) {
        segment = Path()..moveTo(p.dx, p.dy);
        segments.add(segment);
      } else {
        segment.lineTo(p.dx, p.dy);
      }
    }

    for (final path in segments) {
      final fillPath = Path.from(path)
        ..lineTo(stepX * (values.length - 1), size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      canvas.drawPath(path, linePaint);
    }

    final dotPaint = Paint()..color = color;
    final dotHalo = Paint()..color = AppColors.surface;
    for (var i = 0; i < values.length; i++) {
      final p = pointAt(i);
      if (p == null) continue;
      canvas.drawCircle(p, 4, dotHalo);
      canvas.drawCircle(p, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values || old.color != color;
}
