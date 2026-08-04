import 'package:flutter/material.dart';

import '../config/constants.dart';

/// Line-chart card for one metric over time (daily output, LOR%, rejection
/// count). Null entries (no data logged that day) leave a gap in the line
/// rather than dropping to zero.
///
/// One series, one hue — a legend would just restate the title, so instead
/// the latest value rides as a direct-labelled badge and the y-axis carries
/// clean rounded gridline values. Tap or drag anywhere on the plot for a
/// crosshair + exact value at that day; nothing here is tooltip-only — the
/// same figures are also in the "Daily figures" table alongside it.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.title,
    required this.dates,
    required this.values,
    required this.color,
    this.suffix = '',
    this.latestLabel = 'Today',
  });

  final String title;
  final List<String> dates;
  final List<double?> values;
  final Color color;

  /// Appended to the latest-value badge and axis labels, e.g. "%".
  final String suffix;

  /// What the top-right badge calls the last point, e.g. "Today".
  final String latestLabel;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _touchIndex;

  bool get _hasData => widget.values.any((v) => v != null);

  void _updateTouch(Offset local, Size size) {
    if (widget.values.length < 2) return;
    final step = size.width / (widget.values.length - 1);
    final i = (local.dx / step).round().clamp(0, widget.values.length - 1);
    if (widget.values[i] == null) return;
    setState(() => _touchIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.values.isNotEmpty ? widget.values.last : null;

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
                  widget.title,
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
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.latestLabel}: ${_formatValue(latest)}${widget.suffix}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: widget.color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: _hasData
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (d) => _updateTouch(d.localPosition, size),
                        onPanUpdate: (d) => _updateTouch(d.localPosition, size),
                        onPanEnd: (_) => setState(() => _touchIndex = null),
                        onTapUp: (d) => _updateTouch(d.localPosition, size),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _LineChartPainter(
                            values: widget.values,
                            color: widget.color,
                            gridColor: AppColors.chartGrid,
                            axisColor: AppColors.chartAxisLabel,
                            surfaceColor: AppColors.surface,
                            suffix: widget.suffix,
                            touchIndex: _touchIndex,
                          ),
                        ),
                      );
                    },
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
          if (widget.dates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_shortDate(widget.dates.first), style: _axisStyle),
                if (_touchIndex != null &&
                    _touchIndex! > 0 &&
                    _touchIndex! < widget.dates.length - 1)
                  Text(
                    _shortDate(widget.dates[_touchIndex!]),
                    style: _axisStyle.copyWith(
                      color: widget.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(_shortDate(widget.dates.last), style: _axisStyle),
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
  _LineChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.axisColor,
    required this.surfaceColor,
    required this.suffix,
    required this.touchIndex,
  });

  final List<double?> values;
  final Color color;
  final Color gridColor;
  final Color axisColor;
  final Color surfaceColor;
  final String suffix;
  final int? touchIndex;

  /// Rounds a chart ceiling up to a "clean" step (1/2/5 × a power of ten) so
  /// gridline labels read as round numbers instead of "83.7".
  static double _niceCeiling(double value) {
    if (value <= 0) return 1;
    final magnitude = _pow10Floor(value);
    final normalized = value / magnitude;
    final step = normalized <= 1
        ? 1.0
        : normalized <= 2
        ? 2.0
        : normalized <= 5
        ? 5.0
        : 10.0;
    return step * magnitude;
  }

  static double _pow10Floor(double v) {
    var m = 1.0;
    while (m * 10 <= v) {
      m *= 10;
    }
    while (m > v) {
      m /= 10;
    }
    return m;
  }

  String _label(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    // Leave room on the left for y-axis value labels.
    const axisWidth = 34.0;
    final plotLeft = axisWidth;
    final plotWidth = size.width - axisWidth;

    final nonNull = values.whereType<double>();
    final maxV = nonNull.isEmpty
        ? 1.0
        : nonNull.reduce((a, b) => a > b ? a : b);
    final top = _niceCeiling(maxV <= 0 ? 1 : maxV);

    // Hairline gridlines at 0 / half / top, each with a rounded value label —
    // solid, never dashed, one step off the surface.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(plotLeft, y), Offset(size.width, y), gridPaint);
      final labelValue = top - (top * i / 2);
      labelPainter.text = TextSpan(
        text: _label(labelValue) + suffix,
        style: TextStyle(
          fontSize: 10,
          color: axisColor,
          fontWeight: FontWeight.w600,
        ),
      );
      labelPainter.layout(maxWidth: axisWidth - 4);
      labelPainter.paint(
        canvas,
        Offset(0, (y - labelPainter.height / 2).clamp(0, size.height)),
      );
    }

    final stepX = values.length > 1 ? plotWidth / (values.length - 1) : 0.0;
    Offset? pointAt(int i) {
      final v = values[i];
      if (v == null) return null;
      final x = plotLeft + stepX * i;
      final y = size.height - (v / top) * size.height;
      return Offset(x, y.clamp(0, size.height));
    }

    // Build contiguous segments, skipping gaps at null values.
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
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
      // A wash, never a saturated block — 10% opacity per the mark spec.
      final fillPath = Path.from(path)
        ..lineTo(plotLeft + stepX * (values.length - 1), size.height)
        ..lineTo(plotLeft, size.height)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.10));
      canvas.drawPath(path, linePaint);
    }

    // End marker only — selective direct labelling, not a dot on every point.
    Offset? lastPoint;
    for (var i = values.length - 1; i >= 0; i--) {
      final p = pointAt(i);
      if (p != null) {
        lastPoint = p;
        break;
      }
    }
    if (lastPoint != null) {
      canvas.drawCircle(lastPoint, 5, Paint()..color = surfaceColor);
      canvas.drawCircle(lastPoint, 4, Paint()..color = color);
    }

    // Touch crosshair + tooltip.
    if (touchIndex != null) {
      final p = pointAt(touchIndex!);
      final v = values[touchIndex!];
      if (p != null && v != null) {
        final crosshairPaint = Paint()
          ..color = axisColor.withValues(alpha: 0.5)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(p.dx, 0),
          Offset(p.dx, size.height),
          crosshairPaint,
        );
        canvas.drawCircle(p, 6, Paint()..color = surfaceColor);
        canvas.drawCircle(p, 4.5, Paint()..color = color);

        final tooltipText = _label(v) + suffix;
        labelPainter.text = TextSpan(
          text: tooltipText,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        );
        labelPainter.layout();
        final bubbleWidth = labelPainter.width + 16;
        final bubbleHeight = labelPainter.height + 10;
        var bubbleX = p.dx - bubbleWidth / 2;
        bubbleX = bubbleX.clamp(plotLeft, size.width - bubbleWidth);
        var bubbleY = p.dy - bubbleHeight - 10;
        if (bubbleY < 0) bubbleY = p.dy + 10;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(bubbleX, bubbleY, bubbleWidth, bubbleHeight),
          const Radius.circular(6),
        );
        canvas.drawRRect(rect, Paint()..color = color);
        labelPainter.paint(canvas, Offset(bubbleX + 8, bubbleY + 5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values ||
      old.color != color ||
      old.touchIndex != touchIndex;
}
