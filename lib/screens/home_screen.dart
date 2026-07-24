import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../config/theme_controller.dart';
import '../widgets/area_card.dart';
import '../widgets/hicom_app_bar.dart';
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

  void _showAccountPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('User accounts & login are coming soon'),
          behavior: SnackBarBehavior.floating,
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
          IconButton(
            icon: const Icon(Icons.account_circle_rounded),
            tooltip: 'Account',
            onPressed: () => _showAccountPlaceholder(context),
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
          // ignore: prefer_const_constructors
          children: [_LogTab(), DashboardScreen()],
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

/// The original home content: pick a production area to log.
class _LogTab extends StatelessWidget {
  const _LogTab();

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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.navy,
                ),
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
          'Tap a module to view machines and log output',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        AreaCard(
          title: 'Casting',
          subtitle: 'Die-casting machines · hourly output by DCM & part',
          icon: Icons.local_fire_department_rounded,
          onTap: () => _open(context, const CastingHomeScreen()),
        ),
        const SizedBox(height: AppDimens.fieldSpacing),
        AreaCard(
          title: 'Secondary',
          subtitle: 'Finishing stations · actual output & LOR%',
          icon: Icons.handyman_rounded,
          onTap: () => _open(context, const SecondaryHomeScreen()),
        ),
        const SizedBox(height: AppDimens.fieldSpacing),
        AreaCard(
          title: 'Machining',
          subtitle: 'CNC lines by customer · output & rejection',
          icon: Icons.precision_manufacturing_rounded,
          onTap: () => _open(context, const MachiningHomeScreen()),
        ),
      ],
    );
  }
}
