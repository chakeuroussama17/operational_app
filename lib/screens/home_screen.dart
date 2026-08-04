import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../config/theme_controller.dart';
import '../models/app_user.dart';
import '../widgets/area_card.dart';
import '../widgets/hicom_app_bar.dart';
import 'auth_gate.dart';
import 'casting_home_screen.dart';
import 'dashboard_screen.dart';
import 'machining_home_screen.dart';
import 'secondary_home_screen.dart';

/// App root: bottom nav between the Log tab (pick a module, enter data) and
/// the Dashboard tab (real-time analytics). Owns the persistent app bar,
/// including the (placeholder) user-account icon.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  static const _titles = ['Production Shift Log', 'Dashboard — Analytics'];

  /// The modules this person may work in. Without a signed-in user (widget
  /// tests) that's all of them; the backend refuses anything out of scope
  /// regardless of what the app draws.
  List<String> get _visibleModules =>
      _user?.allowedModules ?? [for (final d in departments) d.toLowerCase()];

  /// Who is signed in — null in widget tests, which pump this screen without
  /// a gate above it and therefore see every module.
  AppUser? get _user => AuthScope.maybeOf(context)?.user;

  void _showAccount(BuildContext context) {
    final user = _user;
    if (user == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  String _themeTooltip(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Theme: follow system (tap for light)',
    ThemeMode.light => 'Theme: light (tap for dark)',
    ThemeMode.dark => 'Theme: dark (tap to follow system)',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle: _titles[_tabIndex],
        actions: [
          IconButton(
            icon: Icon(_themeIcon(themeController.value)),
            tooltip: _themeTooltip(themeController.value),
            onPressed: () => themeController.cycle(),
          ),
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.account_circle_rounded),
              tooltip: 'Account',
              onPressed: () => _showAccount(context),
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        // Deliberately NOT const: these must rebuild (and re-read AppColors)
        // on a theme toggle, which flows down from the root App rebuilding
        // this whole tree. A const child would be canonicalised and skipped.
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _LogTab(modules: _visibleModules),
            DashboardScreen(modules: _visibleModules),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceTint,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_rounded),
            selectedIcon: Icon(Icons.edit_note_rounded, color: AppColors.navy),
            label: 'Log',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_rounded),
            selectedIcon: Icon(Icons.insights_rounded, color: AppColors.navy),
            label: 'Dashboard',
          ),
        ],
      ),
    );
  }
}

/// One line of the account dialog.
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

/// The original home content: pick a production area to log — narrowed to the
/// modules this person's department covers.
class _LogTab extends StatelessWidget {
  const _LogTab({required this.modules});

  /// Lowercase module keys, in display order.
  final List<String> modules;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Today's date as "24 July 2026".
  static String _formatToday() {
    final now = DateTime.now();
    return '${now.day} ${_months[now.month - 1]} ${now.year}';
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppDimens.screenPadding),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_rounded,
                    size: 14,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'TODAY · ${_formatToday()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Select production area',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          modules.length == 1
              ? 'Tap to view machines and log output'
              : 'Tap a module to view machines and log output',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        for (final module in modules) ...[
          _cardFor(context, module),
          const SizedBox(height: AppDimens.fieldSpacing),
        ],
      ],
    );
  }

  Widget _cardFor(BuildContext context, String module) => switch (module) {
    'casting' => AreaCard(
      title: 'Casting',
      subtitle: 'Die-casting machines · hourly output by DCM & part',
      icon: Icons.local_fire_department_rounded,
      onTap: () => _open(context, const CastingHomeScreen()),
    ),
    'secondary' => AreaCard(
      title: 'Secondary',
      subtitle: 'Finishing stations · actual output & LOR%',
      icon: Icons.handyman_rounded,
      onTap: () => _open(context, const SecondaryHomeScreen()),
    ),
    _ => AreaCard(
      title: 'Machining',
      subtitle: 'CNC lines by customer · output & rejection',
      icon: Icons.precision_manufacturing_rounded,
      onTap: () => _open(context, const MachiningHomeScreen()),
    ),
  };
}
