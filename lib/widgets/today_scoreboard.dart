import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/analytics_models.dart';

/// Home's headline: today's output as a live scoreboard rather than three
/// static tiles — a number that counts up to where the plant stands and a
/// bar against today's plan. Each module's own figure and its week-long
/// sparkline sit on that module's tile below, so no name appears twice.
class TodayScoreboard extends StatelessWidget {
  const TodayScoreboard({
    super.key,
    required this.modules,
    required this.series,
    required this.loading,
  });

  /// Lowercase module keys, in display order.
  final List<String> modules;

  /// Each module's last seven days, today last.
  final Map<String, AnalyticsSeries> series;
  final bool loading;

  static double _last(List<double> v) => v.isEmpty ? 0 : v.last;

  double get _output {
    var total = 0.0;
    for (final s in series.values) {
      total += _last(s.output);
    }
    return total;
  }

  double get _plan {
    var total = 0.0;
    for (final s in series.values) {
      total += _last(s.plan);
    }
    return total;
  }

  double? get _lor {
    final values = [
      for (final s in series.values)
        if (s.lorPercent.isNotEmpty && s.lorPercent.last != null)
          s.lorPercent.last!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double get _rejects {
    var total = 0.0;
    for (final s in series.values) {
      total += _last(s.rejection);
    }
    return total;
  }

  /// Machines/stations/customers that logged anything today — read from the
  /// per-group daily series, so a seven-day window does not inflate it.
  int get _reporting {
    var count = 0;
    for (final s in series.values) {
      for (final daily in s.groupSeries.values) {
        if (daily.isNotEmpty && daily.last > 0) count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final hasData = !loading && series.isNotEmpty;
    final output = _output;
    final plan = _plan;
    final lor = _lor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.authViolet.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.authViolet.withValues(alpha: 0.18),
            blurRadius: 20,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OUTPUT TODAY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (hasData)
                CountUp(
                  value: output,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: AppColors.textPrimary,
                  ),
                )
              else
                Text(
                  '—',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: AppColors.textPrimary,
                  ),
                ),
              if (hasData) ...[
                const SizedBox(width: 6),
                Text(
                  'pcs',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (hasData && plan > 0) ...[
            const SizedBox(height: 12),
            _PlanBar(output: output, plan: plan),
          ] else if (hasData) ...[
            const SizedBox(height: 6),
            Text(
              'No plan set for today yet',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                label: 'Avg LOR',
                value: lor == null ? '—' : '${lor.toStringAsFixed(1)}%',
                color: AppColors.steelBlue,
              ),
              if (modules.contains('machining'))
                _Chip(
                  label: 'Rejects',
                  value: hasData ? _fmt(_rejects) : '—',
                  color: AppColors.amberDark,
                )
              else
                _Chip(
                  label: 'Reporting',
                  value: hasData ? '$_reporting' : '—',
                  color: AppColors.amberDark,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmt(double v) => groupThousands(v.round());

/// 12480 -> "12,480": a big number is read at a glance only if it is grouped.
String groupThousands(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A number that counts up to its value on first show and eases between
/// values afterwards, so a refresh reads as the total moving, not a flicker.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.style});

  final double value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(_fmt(v), style: style),
    );
  }
}

class _PlanBar extends StatelessWidget {
  const _PlanBar({required this.output, required this.plan});

  final double output;
  final double plan;

  @override
  Widget build(BuildContext context) {
    final fraction = (output / plan).clamp(0.0, 1.0);
    final met = output >= plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: AppColors.surfaceTint,
              valueColor: AlwaysStoppedAnimation(
                met ? AppColors.success : AppColors.authViolet,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'of ${_fmt(plan)} planned · ${(output / plan * 100).round()}%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: met ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A week at a glance: the shape of the line, not its values. The last point
/// — today — is marked, because that is the one being compared.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(
        values: values,
        color: AppColors.authViolet,
        dot: AppColors.authPink,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color, required this.dot});

  final List<double> values;
  final Color color;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    const pad = 3.0;
    Offset at(int i) => Offset(
      pad + (size.width - pad * 2) * i / (values.length - 1),
      size.height - pad - (size.height - pad * 2) * (values[i] - minV) / span,
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(at(values.length - 1), 3, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color || old.dot != dot;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
