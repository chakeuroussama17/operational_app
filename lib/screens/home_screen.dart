import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../config/theme_controller.dart';
import '../models/analytics_models.dart';
import '../models/app_user.dart';
import '../services/sheets_service.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/home_widgets.dart';
import 'auth_gate.dart';
import 'casting_home_screen.dart';
import 'dashboard_screen.dart';
import 'machining_home_screen.dart';
import 'secondary_home_screen.dart';

/// App root: bottom nav between the Log tab (pick a module, enter data) and
/// the Dashboard tab (real-time analytics). Owns the persistent app bar and
/// the account/theme actions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.service});

  /// Test seam: the Log tab's KPI strip normally builds its own
  /// [SheetsService]; widget tests inject one backed by a mock client.
  final SheetsService? service;

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
            _LogTab(modules: _visibleModules, service: widget.service),
            DashboardScreen(modules: _visibleModules),
          ],
        ),
      ),
      // Follows the app's light/dark setting like every other surface; the
      // brand accent rides the selection indicator rather than the whole bar.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.authViolet.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? AppColors.authViolet
                : AppColors.textSecondary,
          ),
        ),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.edit_note_rounded, color: AppColors.textSecondary),
            selectedIcon: Icon(
              Icons.edit_note_rounded,
              color: AppColors.authViolet,
            ),
            label: 'Log',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_rounded, color: AppColors.textSecondary),
            selectedIcon: Icon(
              Icons.insights_rounded,
              color: AppColors.authViolet,
            ),
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

/// The home content: today's headline numbers, then the production areas to
/// log into. Styled to the auth screens rather than the working screens —
/// this is where you land, not where you work.
class _LogTab extends StatefulWidget {
  const _LogTab({required this.modules, this.service});

  /// Lowercase module keys, in display order.
  final List<String> modules;
  final SheetsService? service;

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  late final _service = widget.service ?? SheetsService();

  /// Today's slice per module. Absent until it arrives; a failed fetch just
  /// leaves the KPI tiles showing "—" rather than blocking the page — the
  /// point of this screen is the buttons underneath, and those always work.
  final Map<String, AnalyticsSeries> _series = {};
  bool _loading = true;

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

  static const _icons = {
    'casting': Icons.local_fire_department_rounded,
    'secondary': Icons.handyman_rounded,
    'machining': Icons.precision_manufacturing_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadKpis();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadKpis() async {
    setState(() => _loading = true);
    try {
      final modules = widget.modules;
      final results = await Future.wait([
        for (final module in modules)
          _service.fetchAnalytics(module: module, days: 1),
      ]);
      if (!mounted) return;
      setState(() {
        _series
          ..clear()
          ..addEntries([
            for (var i = 0; i < modules.length; i++)
              MapEntry(modules[i], results[i]),
          ]);
        _loading = false;
      });
    } on SheetsSubmissionException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Today's date as "24 July 2026".
  static String _formatToday() {
    final now = DateTime.now();
    return '${now.day} ${_months[now.month - 1]} ${now.year}';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  double get _todayOutput {
    var total = 0.0;
    for (final s in _series.values) {
      if (s.output.isNotEmpty) total += s.output.last;
    }
    return total;
  }

  double? get _todayLor {
    final values = [
      for (final s in _series.values)
        if (s.lorPercent.isNotEmpty && s.lorPercent.last != null)
          s.lorPercent.last!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double get _todayRejections {
    var total = 0.0;
    for (final s in _series.values) {
      if (s.rejection.isNotEmpty) total += s.rejection.last;
    }
    return total;
  }

  /// How many machines/stations/customers reported anything today — the
  /// stand-in third KPI for departments that don't track rejections.
  int get _reportingCount {
    var count = 0;
    for (final s in _series.values) {
      count += s.byGroup.length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final showRejections = widget.modules.contains('machining');
    final hasData = _series.isNotEmpty;
    final lor = _todayLor;

    return HomeBackdrop(
      child: RefreshIndicator(
        color: AppColors.authPink,
        backgroundColor: AppColors.surface,
        onRefresh: _loadKpis,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Center(
              child: HomeHeroBadge(
                icon: _icons[widget.modules.first] ?? Icons.factory_rounded,
                // The one illustration we have is a die-casting cell, so it
                // only stands in where casting is actually on screen; the
                // other departments keep the gradient tile until they have
                // artwork of their own.
                imageAsset: widget.modules.contains('casting')
                    ? 'assets/hero_casting.png'
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                widget.modules.length == 1
                    ? _titleFor(widget.modules.first)
                    : 'HICOM Diecastings',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'TODAY · ${_formatToday()}'.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: HomeKpiTile(
                    label: 'Output',
                    value: _loading || !hasData ? '—' : _fmt(_todayOutput),
                    unit: _loading || !hasData ? null : 'pcs',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HomeKpiTile(
                    label: 'Avg LOR',
                    value: lor == null ? '—' : lor.toStringAsFixed(1),
                    unit: lor == null ? null : '%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: showRejections
                      ? HomeKpiTile(
                          label: 'Rejects',
                          value: _loading || !hasData
                              ? '—'
                              : _fmt(_todayRejections),
                          unit: _loading || !hasData ? null : 'pcs',
                        )
                      : HomeKpiTile(
                          label: 'Reporting',
                          value: _loading || !hasData
                              ? '—'
                              : '$_reportingCount',
                        ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              'Select production area',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.modules.length == 1
                  ? 'Tap to view machines and log output'
                  : 'Tap a module to view machines and log output',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            for (final module in widget.modules) ...[
              _tileFor(context, module),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  static String _titleFor(String module) => switch (module) {
    'casting' => 'Casting',
    'secondary' => 'Secondary',
    _ => 'Machining',
  };

  Widget _tileFor(BuildContext context, String module) => switch (module) {
    'casting' => HomeModuleTile(
      title: 'Casting',
      subtitle: 'Die-casting machines · hourly output by DCM & part',
      icon: Icons.local_fire_department_rounded,
      onTap: () => _open(context, const CastingHomeScreen()),
    ),
    'secondary' => HomeModuleTile(
      title: 'Secondary',
      subtitle: 'Finishing stations · actual output & LOR%',
      icon: Icons.handyman_rounded,
      onTap: () => _open(context, const SecondaryHomeScreen()),
    ),
    _ => HomeModuleTile(
      title: 'Machining',
      subtitle: 'CNC lines by customer · output & rejection',
      icon: Icons.precision_manufacturing_rounded,
      onTap: () => _open(context, const MachiningHomeScreen()),
    ),
  };
}
