import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/constants.dart';

/// "Tank" score card that fills bottom-up with green fluid according to
/// [fillPercent] (0-100). The fill level animates on every change, with a
/// wavy fluid surface; at 100% the card gets a green border + checkmark.
class FillTankCard extends StatelessWidget {
  const FillTankCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.fillPercent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int fillPercent;
  final VoidCallback onTap;

  static const Color _fillColor = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    final complete = fillPercent >= 100;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fillPercent.clamp(0, 100) / 100),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      builder: (context, level, _) {
        return Material(
          color: AppColors.surface,
          elevation: 2,
          shadowColor: Colors.black26,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.cardRadius),
            side: BorderSide(
              color: complete ? AppColors.success : AppColors.borderSubtle,
              width: complete ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _WavePainter(level: level)),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            shadows: const [
                              Shadow(color: Colors.white70, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Part names off the master list can be long — clamp them
                      // so the tile never overflows its fixed square.
                      Flexible(
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            shadows: const [
                              Shadow(color: Colors.white70, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$fillPercent% logged',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: complete
                              ? AppColors.success
                              : AppColors.steelBlue,
                          shadows: const [
                            Shadow(color: Colors.white70, blurRadius: 6),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (complete)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Paints the rising fluid: a gradient body with a sinusoidal surface plus
/// a lighter back wave for depth. The wave flattens near empty and full.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.level});

  /// 0..1 fill level (bottom-up).
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final l = level.clamp(0.0, 1.0);
    if (l <= 0.004) return;

    final baseY = size.height * (1 - l);
    final amp = 5.0 * (1 - (2 * l - 1).abs());
    final phase = l * math.pi * 4;

    Path wave(double ampScale, double phaseShift) {
      final path = Path()
        ..moveTo(
          0,
          _surfaceY(0, size, baseY, amp * ampScale, phase + phaseShift),
        );
      const steps = 24;
      for (var i = 1; i <= steps; i++) {
        final x = size.width * i / steps;
        path.lineTo(
          x,
          _surfaceY(i / steps, size, baseY, amp * ampScale, phase + phaseShift),
        );
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      return path;
    }

    canvas.drawPath(
      wave(1.7, math.pi / 2.5),
      Paint()..color = FillTankCard._fillColor.withValues(alpha: 0.30),
    );

    final bodyPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              FillTankCard._fillColor.withValues(alpha: 0.75),
              FillTankCard._fillColor,
            ],
          ).createShader(
            Rect.fromLTWH(0, baseY - 10, size.width, size.height - baseY + 10),
          );
    canvas.drawPath(wave(1, 0), bodyPaint);
  }

  double _surfaceY(
    double t,
    Size size,
    double baseY,
    double amp,
    double phase,
  ) => baseY + math.sin(phase + t * math.pi * 2) * amp;

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.level != level;
}
