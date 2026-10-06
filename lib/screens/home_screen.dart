import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../models/app_user.dart';
import '../services/sheets_service.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/home_widgets.dart';
import '../widgets/today_scoreboard.dart';
import 'auth_gate.dart';
import 'casting_home_screen.dart';
import 'dashboard_screen.dart';
import 'tables_screen.dart';
import 'machining_operations_screen.dart';
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

  /// Neither the Dashboard nor the Tables tab is built until first opened.
  /// All three live in an IndexedStack (so their state survives switching),
  /// but that also means all three would fetch on launch — tripling the
  /// requests before the first screen has even painted, on a backend where
  /// each one costs seconds. Each stays mounted once visited.
  bool _dashboardOpened = false;
  bool _tablesOpened = false;

  static const _titles = [
    'Production Shift Log',
    'Dashboard — Analytics',
    'Sheet tables',
  ];

  /// The modules this person may work in. Without a signed-in user (widget
  /// tests) that's all of them; the backend refuses anything out of scope
  /// regardless of what the app draws.
  List<String> get _visibleModules =>
      _user?.allowedModules ?? [for (final d in departments) d.toLowerCase()];

  /// Who is signed in — null in widget tests, which pump this screen without
  /// a gate above it and therefore see every module.
  AppUser? get _user => AuthScope.maybeOf(context)?.user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Theme, account and sign-out come with the bar, on every page.
      appBar: HicomAppBar(subtitle: _titles[_tabIndex]),
      body: SafeArea(
        bottom: false,
        // Deliberately NOT const: these must rebuild (and re-read AppColors)
        // on a theme toggle, which flows down from the root App rebuilding
        // this whole tree. A const child would be canonicalised and skipped.
        // One wash behind all three tabs, so Dashboard and Tables sit on the
        // same ground as the Log tab instead of on bare theme grey.
        child: HomeBackdrop(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _LogTab(modules: _visibleModules, service: widget.service),
              if (_dashboardOpened)
                DashboardScreen(modules: _visibleModules)
              else
                const SizedBox.shrink(),
              if (_tablesOpened)
                TablesScreen(modules: _visibleModules, service: widget.service)
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      // Follows the app's light/dark setting like every other surface; the
      // brand accent rides the selection indicator rather than the whole bar.
      // A floating pill rather than a full-width slab: it sits ON the
      // gradient wash instead of cutting it off, which is what makes the
      // page read as one surface with a control laid over it.
      extendBody: true,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: AppColors.authViolet.withValues(alpha: 0.30),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.authViolet.withValues(alpha: 0.22),
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: NavigationBar(
              height: 62,
              selectedIndex: _tabIndex,
              onDestinationSelected: (index) => setState(() {
                _tabIndex = index;
                if (index == 1) _dashboardOpened = true;
                if (index == 2) _tablesOpened = true;
              }),
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.authViolet.withValues(alpha: 0.28),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: states.contains(WidgetState.selected)
                      ? AppColors.authViolet
                      : AppColors.textSecondary,
                ),
              ),
              destinations: [
                NavigationDestination(
                  icon: Icon(
                    Icons.edit_note_rounded,
                    color: AppColors.textSecondary,
                  ),
                  selectedIcon: Icon(
                    Icons.edit_note_rounded,
                    color: AppColors.authViolet,
                  ),
                  label: 'Log',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.insights_rounded,
                    color: AppColors.textSecondary,
                  ),
                  selectedIcon: Icon(
                    Icons.insights_rounded,
                    color: AppColors.authViolet,
                  ),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.table_chart_rounded,
                    color: AppColors.textSecondary,
                  ),
                  selectedIcon: Icon(
                    Icons.table_chart_rounded,
                    color: AppColors.authViolet,
                  ),
                  label: 'Tables',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the account dialog.
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
          // A week, not a day: today is the last point, and the six before
          // it are the sparkline that says whether today is up or down.
          _service.fetchAnalytics(module: module, days: 7),
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

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    // The wash is painted once, behind the whole IndexedStack.
    return RefreshIndicator(
      color: AppColors.authPink,
      backgroundColor: AppColors.surface,
      onRefresh: _loadKpis,
      child: ListView(
        // The nav bar floats over the page (extendBody), so the list must end
        // above it — otherwise the last tile can never scroll fully into
        // view. The scaffold reports the bar's height as bottom padding.
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: HomeHeroBadge(
              // Smaller on a phone so the module tile shows without scrolling.
              size: MediaQuery.sizeOf(context).height < 760 ? 100 : 132,
              icon: _icons[widget.modules.first] ?? Icons.factory_rounded,
              // Everyone gets the artwork — it's the company's own plant,
              // not a per-department badge, and a machining supervisor
              // landing on a plain icon while casting gets a render reads
              // as a half-finished app rather than as scoping.
              imageAsset: 'assets/hero_casting.png',
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
          const SizedBox(height: 16),
          TodayScoreboard(
            modules: widget.modules,
            series: _series,
            loading: _loading,
          ),
          const SizedBox(height: 20),
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
    );
  }

  /// Today's pieces for one module, once its figures have arrived.
  double? _todayFor(String module) {
    final output = _series[module]?.output;
    return output == null || output.isEmpty ? null : output.last;
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
      heroTag: 'module:casting',
      today: _todayFor('casting'),
      week: _series['casting']?.output,
      onTap: () => _open(context, const CastingHomeScreen()),
    ),
    'secondary' => HomeModuleTile(
      title: 'Secondary',
      subtitle: 'Finishing stations · actual output & LOR%',
      icon: Icons.handyman_rounded,
      heroTag: 'module:secondary',
      today: _todayFor('secondary'),
      week: _series['secondary']?.output,
      onTap: () => _open(context, const SecondaryHomeScreen()),
    ),
    _ => HomeModuleTile(
      title: 'Machining',
      subtitle: 'Machining & assembly · output & rejection',
      icon: Icons.precision_manufacturing_rounded,
      heroTag: 'module:machining',
      today: _todayFor('machining'),
      week: _series['machining']?.output,
      onTap: () => _open(context, const MachiningOperationsScreen()),
    ),
  };
}
