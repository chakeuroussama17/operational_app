import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../config/theme_controller.dart';
import '../screens/auth_gate.dart';

/// Branded app bar, shown on every screen: the HICOM logo on the magenta→
/// violet band that carries the login screen and the home hero, curved off
/// at the bottom so it reads as a card laid over the page rather than as a
/// slab bolted to the top. [subtitle] names the current screen
/// ("Casting — Machines"); [actions] adds trailing icon buttons.
///
/// Everything is laid out on one baseline grid — a fixed 52px content row
/// with the logo, the wordmark block and the actions all vertically centred
/// in it — so the bar looks identical from screen to screen instead of
/// shifting as the subtitle comes and goes.
/// Cycles system -> light -> dark. Listens to the controller itself, so its
/// icon follows the switch on whichever page it was pressed.
class _ThemeButton extends StatelessWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final mode = themeController.value;
        final floor = themeController.floor;
        return IconButton(
          onPressed: themeController.cycle,
          color: Colors.white,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            floor
                ? Icons.contrast_rounded
                : switch (mode) {
                    ThemeMode.system => Icons.brightness_auto_rounded,
                    ThemeMode.light => Icons.light_mode_rounded,
                    ThemeMode.dark => Icons.dark_mode_rounded,
                  },
            size: 22,
          ),
          tooltip: floor
              ? 'Theme: floor mode, high contrast (tap to follow system)'
              : switch (mode) {
                  ThemeMode.system => 'Theme: follow system (tap for light)',
                  ThemeMode.light => 'Theme: light (tap for dark)',
                  ThemeMode.dark => 'Theme: dark (tap for floor mode)',
                },
        );
      },
    );
  }
}

/// Who is signed in: name, email, employee ID, department and role.
void showAccountDialog(BuildContext context) {
  final user = AuthScope.maybeOf(context)?.user;
  if (user == null) return;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(user.name.isEmpty ? 'Account' : user.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccountLine(icon: Icons.alternate_email, text: user.email),
          if (user.employeeId.isNotEmpty)
            _AccountLine(
              icon: Icons.badge_outlined,
              text: 'Employee ID ${user.employeeId}',
            ),
          _AccountLine(
            icon: user.isAdmin
                ? Icons.workspace_premium_rounded
                : Icons.factory_rounded,
            text: user.isAdmin
                ? 'Admin — all departments'
                : '${user.department} department',
          ),
          // Worth saying out loud: it is the answer to "why can't I add a
          // part", which is otherwise a button that silently isn't there.
          _AccountLine(
            icon: user.isSuperAdmin
                ? Icons.admin_panel_settings_rounded
                : Icons.person_outline_rounded,
            text: user.isSuperAdmin
                ? 'Super admin — can add parts and customers'
                : 'Operator — logs production',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('CLOSE'),
        ),
      ],
    ),
  );
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 14.5))),
        ],
      ),
    );
  }
}

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

    // The rounded bottom cuts two notches out of the bar, and whatever sits
    // behind the Scaffold shows through them — bare white, since the
    // Scaffold itself is transparent so the page wash can show. Painting the
    // page's own top colour behind the bar fills those notches with the
    // colour the page continues in, instead of with the canvas.
    return ColoredBox(
      color: AppColors.homeBackdrop.first,
      child: Material(
        color: AppColors.authViolet,
        // The curve belongs to the whole bar, so the gradient, the rule and
        // anything that scrolls under it are all clipped by the same shape.
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: _contentHeight + _verticalPadding * 2,
                decoration: const BoxDecoration(
                  gradient: AppColors.authGradient,
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
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                      ),
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
                          //
                          // Every page now carries theme, account and sign-out
                          // beside a back button, and on a 360px phone that
                          // leaves the lockup too little room for both words.
                          // DIECASTINGS gives way first — HICOM alone is the
                          // mark — and scaling down is only the last resort.
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final showTagline = constraints.maxWidth >= 160;
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
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
                                    if (showTagline) ...[
                                      const SizedBox(width: 7),
                                      // Plain white, NOT the magenta→violet shader it
                                      // used to wear. The bar itself is that gradient
                                      // now, so shading the word in the same colours
                                      // painted it onto its own background and made it
                                      // disappear. White is the only thing that reads
                                      // across the whole sweep from pink to violet.
                                      Text(
                                        'DIECASTINGS',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.82,
                                          ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 2.2,
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
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
                    // The same three on every page, so theme, account and
                    // sign-out are never more than one tap away — not only
                    // from home. Theme is always there; account and sign-out
                    // need a session (widget tests pump screens without one).
                    const _ThemeButton(),
                    if (AuthScope.maybeOf(context) != null) ...[
                      IconButton(
                        onPressed: () => showAccountDialog(context),
                        icon: const Icon(
                          Icons.account_circle_rounded,
                          size: 22,
                        ),
                        color: Colors.white,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Account',
                      ),
                      IconButton(
                        onPressed: () => AuthScope.signOutFrom(context),
                        icon: const Icon(Icons.logout_rounded, size: 22),
                        color: Colors.white,
                        visualDensity: VisualDensity.compact,
                        tooltip:
                            'Sign out (${AuthScope.maybeOf(context)!.user.name})',
                      ),
                    ],
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              // The rule that carries the brand accent across every screen.
              Container(
                height: _ruleHeight,
                decoration: const BoxDecoration(
                  gradient: AppColors.authGradient,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
