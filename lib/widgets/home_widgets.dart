import 'package:flutter/material.dart';

import '../config/constants.dart';

/// The dark, branded surface the Log tab sits on — the same magenta-violet
/// family as the auth screens, so signing in and landing on the home page
/// feel like one product rather than two.
class HomeBackdrop extends StatelessWidget {
  const HomeBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B1430), Color(0xFF120E1F), Color(0xFF0B0913)],
        ),
      ),
      child: child,
    );
  }
}

/// The hero badge at the top of the Log tab: a big gradient tile carrying the
/// department's icon, lit from behind so it reads as the screen's focal
/// point.
///
/// Drop-in replacement for a real illustration: pass [imageAsset] (and add it
/// to pubspec) and it shows that instead of the icon, keeping the same glow
/// and frame.
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
    return SizedBox(
      width: size + 60,
      height: size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The glow: a soft pool of brand colour behind the tile.
          Container(
            width: size + 40,
            height: size + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.authViolet.withValues(alpha: 0.55),
                  AppColors.authPink.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Container(
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
                // Gloss: a diagonal white sheen across the top-left, which is
                // what actually sells "shiny" rather than more saturation.
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
                  child: imageAsset != null
                      ? Padding(
                          padding: EdgeInsets.all(size * 0.14),
                          child: Image.asset(imageAsset!, fit: BoxFit.contain),
                        )
                      : Icon(icon, size: size * 0.46, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One headline number on the Log tab, in the auth screens' glass language.
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
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
                      color: Colors.white.withValues(alpha: 0.6),
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
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// A production-area tile on the Log tab — the dark counterpart of the old
/// [AreaCard], carrying a gradient icon chip and a chevron.
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
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
