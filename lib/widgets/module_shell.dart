import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/shift_progress.dart';
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
    this.icon,
    this.heroTag,
  });

  /// The module's icon chip beside the headline. With [heroTag] set it is
  /// where the home tile's chip lands when this screen opens.
  final IconData? icon;
  final Object? heroTag;

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
                    Row(
                      children: [
                        if (icon != null) ...[
                          heroTag == null
                              ? IconChip(icon: icon!, size: 38)
                              : Hero(
                                  tag: heroTag!,
                                  child: IconChip(icon: icon!, size: 38),
                                ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            headline,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
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
    this.progress,
    this.heroTag,
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

  /// When known, replaces the "% logged" bar with an on-pace ring and a
  /// status line — see [ShiftProgress].
  final ShiftProgress? progress;

  /// Flies the icon chip into the screen this card opens, so the step from
  /// list to form reads as one motion rather than a cut.
  final Object? heroTag;

  /// Usually the ⋮ menu. Sits inline rather than stacked over the corner, so
  /// it can never land on top of the title.
  final Widget? trailing;

  /// Tighter padding for the grid layouts.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final percent = fillPercent;
    final pace = progress;
    final health = pace?.health;
    final complete =
        health == PaceHealth.complete ||
        (pace == null && percent != null && percent >= 100);
    // The edge carries the verdict, faintly, so a list of twelve parts can be
    // scanned for the two that need attention without reading any of them.
    final edge = switch (health) {
      PaceHealth.complete => AppColors.success,
      PaceHealth.wellBehind => AppColors.danger.withValues(alpha: 0.6),
      PaceHealth.behind => AppColors.amber.withValues(alpha: 0.7),
      _ => complete ? AppColors.success : AppColors.borderSubtle,
    };
    final edgeWidth =
        health == PaceHealth.wellBehind ||
            health == PaceHealth.behind ||
            complete
        ? 1.5
        : 1.0;
    final chip = IconChip(icon: icon, size: dense ? 38 : 46);

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
            border: Border.all(color: edge, width: edgeWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heroTag == null ? chip : Hero(tag: heroTag!, child: chip),
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
                  if (pace != null) ...[
                    const SizedBox(width: 8),
                    PaceRing(progress: pace),
                  ],
                  ?trailing,
                ],
              ),
              if (pace != null) ...[
                const SizedBox(height: 10),
                _PaceLine(progress: pace),
              ] else if (percent != null) ...[
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

/// Placeholder cards in the shape of the list that is on its way, with a
/// soft shimmer across them. A spinner says "wait"; this says "wait, and here
/// is roughly what you are about to see", so the list arriving does not jolt
/// the page.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 5});

  final int count;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surfaceTint;
    final shine = AppColors.surface;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.screenPadding,
        4,
        AppDimens.screenPadding,
        28,
      ),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => AnimatedBuilder(
        animation: _shimmer,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1.5 + 3 * _shimmer.value, 0),
            end: Alignment(-0.5 + 3 * _shimmer.value, 0),
            colors: [base, shine, base],
          ).createShader(rect),
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(110, 14),
                    const SizedBox(height: 8),
                    bar(170, 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of an entry form: the part in large type, with the same icon chip
/// the part's card carries. With [heroTag] set, that chip is where the card's
/// chip lands when the form opens.
class EntryTitle extends StatelessWidget {
  const EntryTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.tag_rounded,
    this.heroTag,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final chip = IconChip(icon: icon, size: 46);
    return Row(
      children: [
        heroTag == null ? chip : Hero(tag: heroTag!, child: chip),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
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

/// The colour a pace verdict is drawn in, wherever it is drawn.
Color paceColor(PaceHealth health) => switch (health) {
  PaceHealth.onPace || PaceHealth.complete => AppColors.success,
  PaceHealth.behind => AppColors.amber,
  PaceHealth.wellBehind => AppColors.danger,
  PaceHealth.unknown => AppColors.authViolet,
};

String _fmtCount(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Output against plan as a ring: how much of the WHOLE shift's plan is made,
/// coloured by whether that is on pace for the checkpoints logged so far.
/// Without a plan it shows checkpoints logged, in the neutral colour.
class PaceRing extends StatelessWidget {
  const PaceRing({super.key, required this.progress, this.size = 46});

  final ShiftProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fraction =
        progress.planFraction ??
        (progress.total == 0 ? 0.0 : progress.filled / progress.total);
    final color = paceColor(progress.health);
    final label = progress.hasPlan
        ? '${(progress.actual / progress.plan! * 100).round()}%'
        : '${progress.filled}/${progress.total}';
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
            value: v,
            color: color,
            track: AppColors.surfaceTint,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: size * 0.24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.5;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arc, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * value, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// "210 of 900 · on pace", and a downtime badge when the line has stopped.
class _PaceLine extends StatelessWidget {
  const _PaceLine({required this.progress});

  final ShiftProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final health = p.health;
    final color = health == PaceHealth.unknown
        ? AppColors.textSecondary
        : (health == PaceHealth.behind
              ? AppColors.amberDark
              : paceColor(health));
    final String text;
    if (!p.hasPlan) {
      text = p.filled == 0
          ? 'No entries yet'
          : '${p.filled} of ${p.total} checkpoints · no plan set';
    } else if (p.filled == 0) {
      text = 'Plan ${_fmtCount(p.plan!)} · nothing logged yet';
    } else {
      final made = '${_fmtCount(p.actual)} of ${_fmtCount(p.plan!)}';
      text = switch (health) {
        PaceHealth.complete => 'Shift complete · $made',
        PaceHealth.onPace => '$made · on pace',
        PaceHealth.behind => '$made · behind pace',
        PaceHealth.wellBehind => '$made · well behind',
        PaceHealth.unknown => made,
      };
    }
    return Row(
      children: [
        Icon(
          switch (health) {
            PaceHealth.complete => Icons.check_circle,
            PaceHealth.onPace => Icons.trending_up_rounded,
            PaceHealth.behind => Icons.trending_flat_rounded,
            PaceHealth.wellBehind => Icons.trending_down_rounded,
            PaceHealth.unknown => Icons.radio_button_unchecked_rounded,
          },
          size: 14,
          color: color,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (p.downtime > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off_outlined,
                  size: 12,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 3),
                Text(
                  '${_fmtCount(p.downtime)} min',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The gradient square the home screen puts every icon in. Public so the
/// screens a card opens can draw the same chip as a hero landing spot.
class IconChip extends StatelessWidget {
  const IconChip({super.key, required this.icon, required this.size});

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
