import 'package:flutter/material.dart';

import '../config/constants.dart';
import 'hicom_app_bar.dart';
import 'home_widgets.dart';

/// The home screen's look, made reusable.
///
/// Home was restyled first and everything below it kept the old flat-grey
/// treatment, so walking from the module list into a machine list felt like
/// leaving the app. These two pieces are the whole of that look — the
/// backdrop wash and the card — so a screen adopts it by using them rather
/// than by copying colours around.

/// Scaffold + app bar + the gradient wash, with the two-line section header
/// the home screen introduced ("Select production area" / hint beneath).
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({
    super.key,
    required this.subtitle,
    required this.headline,
    required this.child,
    this.hint,
    this.leading,
    this.actions,
  });

  /// Shown in the app bar under the wordmark.
  final String subtitle;

  /// "Select machine", "Select part" — the question this screen asks.
  final String headline;

  /// The smaller line under it. Null when the headline says enough.
  final String? hint;

  /// Sits above the headline: a shift toggle, context chips, whatever the
  /// screen needs before its list.
  final Widget? leading;

  final List<Widget>? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The wash is the background, so the Scaffold must not paint over it.
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: HicomAppBar(subtitle: subtitle, actions: actions),
      body: HomeBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.screenPadding,
                  AppDimens.screenPadding,
                  AppDimens.screenPadding,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(height: 16),
                    ],
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        hint!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scaffold + app bar + the wash, with no section header — for screens that
/// lead with their own context (the entry forms open with chips naming the
/// machine, part and shift, which would read as a second heading under one).
class BackdropScaffold extends StatelessWidget {
  const BackdropScaffold({
    super.key,
    required this.subtitle,
    required this.child,
    this.actions,
  });

  final String subtitle;
  final List<Widget>? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: HicomAppBar(subtitle: subtitle, actions: actions),
      body: HomeBackdrop(child: SafeArea(child: child)),
    );
  }
}

/// The home module tile, generalised: gradient icon chip, title, subtitle,
/// and an optional progress bar for the levels that track completion.
///
/// Replaces the per-screen `_DcmCard`/`_CustomerCard`/`_PartCard` trio and
/// the wave-filled tank, which were three different answers to the same
/// question. Progress reads as a slim bar under the text — the same
/// information the tank carried, in a shape that survives a narrow tile and
/// sits beside the other cards without shouting.
class SelectorCard extends StatelessWidget {
  const SelectorCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.fillPercent,
    this.trailing,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  /// 0-100 when this level tracks how much of the shift is logged; null when
  /// it is only a step on the way somewhere.
  final int? fillPercent;

  /// Usually the ⋮ menu. Sits inline rather than stacked over the corner, so
  /// it can never land on top of the title.
  final Widget? trailing;

  /// Tighter padding for the grid layouts.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final percent = fillPercent;
    final complete = percent != null && percent >= 100;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.all(dense ? 12 : 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: complete ? AppColors.success : AppColors.borderSubtle,
              width: complete ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconChip(icon: icon, size: dense ? 38 : 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Codes run from "1" to "2244-MAR-NO2-BRKT-..." so the
                        // title scales rather than wrapping the card apart.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: dense ? 19 : 17,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              if (percent != null) ...[
                const SizedBox(height: 12),
                _ProgressBar(percent: percent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The gradient square the home screen puts every icon in.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.authGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: AppColors.authPink.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final value = (percent.clamp(0, 100)) / 100;
    final done = percent >= 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: AppColors.surfaceTint,
              valueColor: AlwaysStoppedAnimation(
                done ? AppColors.success : AppColors.authViolet,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            if (done) ...[
              Icon(Icons.check_circle, size: 13, color: AppColors.success),
              const SizedBox(width: 4),
            ],
            Text(
              done ? 'Shift complete' : '$percent% logged',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: done ? AppColors.success : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The dashed "+" tile, restyled to sit beside [SelectorCard].
class AddCard extends StatelessWidget {
  const AddCard({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: DottedRoundedBorder(
          radius: 18,
          color: AppColors.authViolet.withValues(alpha: 0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: AppColors.authViolet, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.authViolet,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline. Flutter has no dashed border, and a plain one
/// would read as another card rather than as an invitation.
class DottedRoundedBorder extends StatelessWidget {
  const DottedRoundedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 18,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    // Walk the outline and draw every other segment.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 6;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius;
}
