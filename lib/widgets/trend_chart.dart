import 'package:flutter/material.dart';

import '../config/constants.dart';

/// One named line on a [TrendChart].
class TrendSeries {
  const TrendSeries({
    required this.name,
    required this.values,
    required this.color,
  });

  final String name;

  /// Null entries (nothing logged that day) leave a gap in the line rather
  /// than dropping it to zero.
  final List<double?> values;
  final Color color;
}

/// Line-chart card for one or more metrics over time.
///
/// A single series gets a filled wash under it and no legend — the title
/// already says what is plotted, so a one-swatch legend would only restate
/// it. Two or more get plain lines plus a legend, which is the dependable
/// identity channel; fills would muddle where they overlap.
///
/// Tap or drag anywhere on the plot for a crosshair and the exact value(s)
/// at that day. Nothing here is tooltip-only — the same figures are in the
/// table alongside.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.title,
    required this.dates,
    required this.series,
    this.suffix = '',
    this.latestLabel = 'Today',
  });

  /// Convenience for the common one-line case.
  TrendChart.single({
    Key? key,
    required String title,
    required List<String> dates,
    required List<double?> values,
    required Color color,
    String suffix = '',
    String latestLabel = 'Today',
  }) : this(
         key: key,
         title: title,
         dates: dates,
         series: [TrendSeries(name: title, values: values, color: color)],
         suffix: suffix,
         latestLabel: latestLabel,
       );

  final String title;
  final List<String> dates;
  final List<TrendSeries> series;

  /// Appended to values in the badge, axis and tooltip, e.g. "%".
  final String suffix;

  /// What the top-right badge calls the last point, e.g. "Today".
  final String latestLabel;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _touchIndex;

  int get _length =>
      widget.series.isEmpty ? 0 : widget.series.first.values.length;

  bool get _hasData => widget.series.any((s) => s.values.any((v) => v != null));

  void _updateTouch(Offset local, Size size) {
    if (_length < 2) return;
    // The plot starts after the y-axis gutter; map the touch into it.
    const axisWidth = 34.0;
    final plotWidth = size.width - axisWidth;
    final step = plotWidth / (_length - 1);
    final i = ((local.dx - axisWidth) / step).round().clamp(0, _length - 1);
    setState(() => _touchIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.series.length == 1;
    final latest = single && widget.series.first.values.isNotEmpty
        ? widget.series.first.values.last
        : null;

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
                    color: widget.series.first.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.latestLabel}: ${_formatValue(latest)}${widget.suffix}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: widget.series.first.color,
                    ),
                  ),
                ),
            ],
          ),
          // A legend is not optional for two or more series — identity must
          // never rest on color-matching alone.
          if (!single) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [for (final s in widget.series) _LegendKey(series: s)],
            ),
          ],
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
                            series: widget.series,
                            fill: single,
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
                      color: AppColors.textPrimary,
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

/// A coloured line-key beside the series name. The text itself stays in the
/// ink tokens — a light categorical hue is illegible as text on the surface.
class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: series.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          series.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.fill,
    required this.gridColor,
    required this.axisColor,
    required this.surfaceColor,
    required this.suffix,
    required this.touchIndex,
  });

  final List<TrendSeries> series;

  /// Only a lone series gets a wash under it.
  final bool fill;
  final Color gridColor;
  final Color axisColor;
  final Color surfaceColor;
  final String suffix;
  final int? touchIndex;

  static const _axisWidth = 34.0;

  /// Rounds a chart ceiling up to a clean step so gridline labels read as
  /// round numbers instead of "83.7".
  ///
  /// The ladder is finer than the usual 1/2/5 because a coarse one wastes the
  /// plot: a series peaking at 105 would jump to a 200 ceiling and use half
  /// the height. Every rung still halves cleanly, since the mid gridline is
  /// labelled too (150 -> 75, 300 -> 150).
  static const _ladder = [1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 10.0];

  static double _niceCeiling(double value) {
    if (value <= 0) return 1;
    final magnitude = _pow10Floor(value);
    final normalized = value / magnitude;
    for (final step in _ladder) {
      if (normalized <= step) return step * magnitude;
    }
    return 10 * magnitude;
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
    if (series.isEmpty) return;
    final length = series.first.values.length;
    if (length == 0) return;

    final plotLeft = _axisWidth;
    final plotWidth = size.width - _axisWidth;

    // One shared scale across every series — never a second y-axis.
    var maxV = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v != null && v > maxV) maxV = v;
      }
    }
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
      labelPainter.layout(maxWidth: _axisWidth - 4);
      labelPainter.paint(
        canvas,
        Offset(0, (y - labelPainter.height / 2).clamp(0, size.height)),
      );
    }

    final stepX = length > 1 ? plotWidth / (length - 1) : 0.0;
    Offset? pointAt(TrendSeries s, int i) {
      final v = s.values[i];
      if (v == null) return null;
      final x = plotLeft + stepX * i;
      final y = size.height - (v / top) * size.height;
      return Offset(x, y.clamp(0, size.height));
    }

    for (final s in series) {
      final linePaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // Contiguous segments, skipping gaps at null values.
      Path? segment;
      final segments = <Path>[];
      for (var i = 0; i < s.values.length; i++) {
        final p = pointAt(s, i);
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
        if (fill) {
          // A wash, never a saturated block — 10% opacity per the mark spec.
          final fillPath = Path.from(path)
            ..lineTo(plotLeft + stepX * (length - 1), size.height)
            ..lineTo(plotLeft, size.height)
            ..close();
          canvas.drawPath(
            fillPath,
            Paint()..color = s.color.withValues(alpha: 0.10),
          );
        }
        canvas.drawPath(path, linePaint);
      }

      // End marker only — selective direct labelling, not a dot per point.
      for (var i = s.values.length - 1; i >= 0; i--) {
        final p = pointAt(s, i);
        if (p != null) {
          canvas.drawCircle(p, 5, Paint()..color = surfaceColor);
          canvas.drawCircle(p, 4, Paint()..color = s.color);
          break;
        }
      }
    }

    if (touchIndex == null) return;
    _paintCrosshair(canvas, size, plotLeft, pointAt, labelPainter);
  }

  void _paintCrosshair(
    Canvas canvas,
    Size size,
    double plotLeft,
    Offset? Function(TrendSeries, int) pointAt,
    TextPainter labelPainter,
  ) {
    final i = touchIndex!;
    // Anchor the crosshair on the first series that has a point here, so it
    // still draws when only one of several logged that day.
    double? x;
    for (final s in series) {
      final p = pointAt(s, i);
      if (p != null) {
        x = p.dx;
        break;
      }
    }
    if (x == null) return;

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = axisColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    final lines = <_TooltipLine>[];
    for (final s in series) {
      final v = s.values[i];
      if (v == null) continue;
      final p = pointAt(s, i)!;
      canvas.drawCircle(p, 6, Paint()..color = surfaceColor);
      canvas.drawCircle(p, 4.5, Paint()..color = s.color);
      lines.add(
        _TooltipLine(
          text: series.length == 1
              ? '${_label(v)}$suffix'
              : '${s.name}  ${_label(v)}$suffix',
          color: s.color,
        ),
      );
    }
    if (lines.isEmpty) return;

    // Measure every line first so the bubble is sized to fit its text — a
    // clipped label is worse than no label.
    var bubbleWidth = 0.0;
    var bubbleHeight = 8.0;
    final laid = <TextPainter>[];
    for (final line in lines) {
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: line.text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      )..layout();
      laid.add(tp);
      final w = tp.width + (series.length == 1 ? 16 : 26);
      if (w > bubbleWidth) bubbleWidth = w;
      bubbleHeight += tp.height + 2;
    }

    var bubbleX = (x - bubbleWidth / 2).clamp(
      plotLeft,
      (size.width - bubbleWidth).clamp(plotLeft, double.infinity),
    );
    var bubbleY = 8.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bubbleX, bubbleY, bubbleWidth, bubbleHeight),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xE6211D3D),
    );

    var y = bubbleY + 4;
    for (var n = 0; n < laid.length; n++) {
      if (series.length > 1) {
        canvas.drawCircle(
          Offset(bubbleX + 9, y + laid[n].height / 2),
          3.5,
          Paint()..color = lines[n].color,
        );
        laid[n].paint(canvas, Offset(bubbleX + 18, y));
      } else {
        laid[n].paint(canvas, Offset(bubbleX + 8, y));
      }
      y += laid[n].height + 2;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series || old.touchIndex != touchIndex || old.fill != fill;
}

class _TooltipLine {
  const _TooltipLine({required this.text, required this.color});

  final String text;
  final Color color;
}
