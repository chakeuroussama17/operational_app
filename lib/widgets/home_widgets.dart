import 'package:flutter/material.dart';

import '../config/constants.dart';

/// The Log tab's backdrop — a wash in the brand hue that follows the app's
/// light/dark setting, so day mode is genuinely light rather than a dimmed
/// version of the dark one.
class HomeBackdrop extends StatelessWidget {
  const HomeBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.homeBackdrop,
        ),
      ),
      child: child,
    );
  }
}

/// The hero at the top of the Log tab, lit from behind so it reads as the
/// screen's focal point.
///
/// With [imageAsset] the illustration floats free on the backdrop with only
/// the glow behind it — a detailed full-colour render would fight a coloured
/// tile around it. Without one it falls back to a gradient tile carrying
/// [icon], which is what the modules with no artwork yet still get.
class HomeHeroBadge extends StatelessWidget {
  const HomeHeroBadge({
    super.key,
    required this.icon,
    this.imageAsset,
    this.size = 132,
  });

  final IconData icon;
  final String? imageAsset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final art = imageAsset != null;
    // The illustration is wide; give it room without inflating the tile case.
    final width = art ? size * 1.75 : size;

    return SizedBox(
      width: width + 60,
      height: size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The glow: a soft pool of brand colour behind the subject.
          Container(
            width: width + 40,
            height: size + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.authViolet.withValues(alpha: art ? 0.38 : 0.55),
                  AppColors.authPink.withValues(alpha: art ? 0.14 : 0.18),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          if (art)
            SizedBox(
              width: width,
              height: size,
              child: Image.asset(
                imageAsset!,
                fit: BoxFit.contain,
                // If the asset is ever missing, fall back to the tile rather
                // than leaving a hole where the hero should be.
                errorBuilder: (context, error, stack) =>
                    _GradientTile(icon: icon, size: size),
              ),
            )
          else
            _GradientTile(icon: icon, size: size),
        ],
      ),
    );
  }
}

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.authGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.authPink.withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Gloss: a diagonal white sheen across the top-left, which is what
          // actually sells "shiny" rather than more saturation.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.38),
                    Colors.white.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 0.75],
                ),
              ),
            ),
          ),
          Center(
            child: Icon(icon, size: size * 0.46, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// One headline number on the Log tab. Uses the app's own surface/ink tokens
/// so it flips with the light/dark setting like every other card.
class HomeKpiTile extends StatelessWidget {
  const HomeKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  final String label;

  /// Pre-formatted, or "—" while loading / when there's nothing to show.
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A production-area tile on the Log tab: a normal card in the app's surface
/// colours, with the brand gradient carried by the icon chip so the accent
/// reads the same in both modes.
class HomeModuleTile extends StatelessWidget {
  const HomeModuleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
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
                  gradient: AppColors.authGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.authPink.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
