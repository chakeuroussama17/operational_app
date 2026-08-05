import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../screens/auth_gate.dart';

/// Branded app bar, shown on every screen: the HICOM logo, a deep-purple
/// header and the magenta→violet rule that ties it to the login screen and
/// the home hero. [subtitle] names the current screen ("Casting — Machines");
/// [actions] adds trailing icon buttons before the sign-out one.
///
/// Everything is laid out on one baseline grid — a fixed 52px content row
/// with the logo, the wordmark block and the actions all vertically centred
/// in it — so the bar looks identical from screen to screen instead of
/// shifting as the subtitle comes and goes.
class HicomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HicomAppBar({super.key, this.subtitle, this.actions});

  final String? subtitle;
  final List<Widget>? actions;

  /// Content row + vertical padding + the 3px accent rule.
  static const double _contentHeight = 52;
  static const double _verticalPadding = 10;
  static const double _ruleHeight = 3;

  @override
  Size get preferredSize => const Size.fromHeight(
    _contentHeight + _verticalPadding * 2 + _ruleHeight,
  );

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Material(
      color: const Color(0xFF241C52),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _contentHeight + _verticalPadding * 2,
              decoration: const BoxDecoration(
                gradient: AppColors.headerGradient,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  if (canPop)
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 24),
                      color: Colors.white,
                      tooltip: 'Back',
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    const SizedBox(width: 10),
                  Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // One line, one baseline: the two words share a
                        // baseline and a single letter-spacing rhythm so the
                        // lockup doesn't look assembled from two fonts.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text(
                              'HICOM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(width: 7),
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) =>
                                  AppColors.authGradient.createShader(bounds),
                              child: const Text(
                                'DIECASTINGS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.2,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null)
                    ...actions!.map(
                      (action) => IconTheme(
                        data: const IconThemeData(
                          color: Colors.white,
                          size: 22,
                        ),
                        child: action,
                      ),
                    ),
                  // Present only when the login gate is active (production) —
                  // widget tests pump screens without an AuthScope and see no
                  // sign-out button.
                  if (AuthScope.maybeOf(context) != null)
                    IconButton(
                      onPressed: () => AuthScope.signOutFrom(context),
                      icon: const Icon(Icons.logout_rounded, size: 22),
                      color: Colors.white,
                      visualDensity: VisualDensity.compact,
                      tooltip:
                          'Sign out (${AuthScope.maybeOf(context)!.user.name})',
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            // The rule that carries the brand accent across every screen.
            Container(
              height: _ruleHeight,
              decoration: const BoxDecoration(gradient: AppColors.authGradient),
            ),
          ],
        ),
      ),
    );
  }
}
