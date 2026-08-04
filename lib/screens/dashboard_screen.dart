import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../services/sheets_service.dart';
import '../widgets/donut_chart.dart';
import '../widgets/error_retry.dart';
import '../widgets/insight_table.dart';
import '../widgets/ranked_bar_chart.dart';
import '../widgets/stat_tile.dart';
import '../widgets/trend_chart.dart';

/// Real-time analytics tab: KPI tiles, trend lines, ranking bars, a defect
/// breakdown and data tables, pulled live from the sheet. Independent of the
/// Log tab — this never writes anything, only reads.
///
/// Shows one section per module the signed-in person's department covers, so
/// a casting supervisor watches casting alone and the admin sees all three.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.modules, this.service});

  /// Lowercase module keys to chart, in display order. Null means all three
  /// (widget tests, which pump this without a signed-in user).
  final List<String>? modules;

  /// Test seam: the screen normally builds its own [SheetsService] against
  /// the real backend; widget tests inject one backed by a mock client.
  final SheetsService? service;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final _sheetsService = widget.service ?? SheetsService();

  bool _everLoaded = false;
  bool _loading = true;
  String? _error;
  int _days = 14;
  final Map<String, AnalyticsSeries> _series = {};

  List<String> get _modules =>
      widget.modules ?? const ['casting', 'secondary', 'machining'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sheetsService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      // A real value already on screen is never blanked mid-refetch — only
      // the first-ever load has nothing to hold onto, so only it shows the
      // full-screen spinner instead of the previous render at reduced opacity.
      _error = null;
    });
    try {
      final modules = _modules;
      final results = await Future.wait([
        for (final module in modules)
          _sheetsService.fetchAnalytics(module: module, days: _days),
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
        _everLoaded = true;
      });
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  static const _titles = {
    'casting': 'Casting',
    'secondary': 'Secondary',
    'machining': 'Machining',
  };
  static const _icons = {
    'casting': Icons.local_fire_department_rounded,
    'secondary': Icons.handyman_rounded,
    'machining': Icons.precision_manufacturing_rounded,
  };
  static const _groupLabels = {
    'casting': 'DCM',
    'secondary': 'Station',
    'machining': 'Customer',
  };

  @override
  Widget build(BuildContext context) {
    if (_loading && !_everLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.steelBlue),
      );
    }
    if (_error != null && !_everLoaded) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      color: AppColors.steelBlue,
      onRefresh: _load,
      child: AnimatedOpacity(
        opacity: _loading ? 0.45 : 1,
        duration: const Duration(milliseconds: 200),
        child: ListView(
          key: const ValueKey('dashboardScrollList'),
          padding: const EdgeInsets.all(AppDimens.screenPadding),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Live totals · last $_days days',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                _RangeChip(
                  label: '7D',
                  selected: _days == 7,
                  onTap: () => _setDays(7),
                ),
                const SizedBox(width: 6),
                _RangeChip(
                  label: '14D',
                  selected: _days == 14,
                  onTap: () => _setDays(14),
                ),
                const SizedBox(width: 6),
                _RangeChip(
                  label: '30D',
                  selected: _days == 30,
                  onTap: () => _setDays(30),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final module in _modules) ...[
              _ModuleSection(
                title: _titles[module] ?? module,
                icon: _icons[module] ?? Icons.factory_rounded,
                groupLabel: _groupLabels[module] ?? 'Group',
                series: _series[module],
                showRejection: module == 'machining',
                singleModule: _modules.length == 1,
              ),
              const SizedBox(height: 26),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Everything for one module: KPI strip, trend lines, a ranking bar of which
/// group is behind, and — Machining only — a rejection breakdown (donut +
/// matching bar) — each backed by a data table twin.
class _ModuleSection extends StatelessWidget {
  const _ModuleSection({
    required this.title,
    required this.icon,
    required this.groupLabel,
    required this.series,
    required this.singleModule,
    this.showRejection = false,
  });

  final String title;
  final IconData icon;

  /// What this module's top-level selector is called ("DCM"/"Station"/
  /// "Customer") — names the ranking bar chart and its table column.
  final String groupLabel;
  final AnalyticsSeries? series;
  final bool showRejection;

  /// True when this is the only module shown (a department-scoped user) —
  /// the header shrinks since the tab title already says which module this is.
  final bool singleModule;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final s = series;
    if (s == null) {
      return _Header(title: title, icon: icon, compact: singleModule);
    }

    final totalOutput = s.output.fold<double>(0, (a, b) => a + b);
    final lorValues = s.lorPercent.whereType<double>();
    final avgLor = lorValues.isEmpty
        ? null
        : lorValues.fold<double>(0, (a, b) => a + b) / lorValues.length;
    final totalRejection = s.rejection.fold<double>(0, (a, b) => a + b);
    final rejectionRate = (totalOutput + totalRejection) > 0
        ? totalRejection / (totalOutput + totalRejection) * 100
        : null;

    var bestDayIndex = -1;
    for (var i = 0; i < s.output.length; i++) {
      if (bestDayIndex == -1 || s.output[i] > s.output[bestDayIndex]) {
        bestDayIndex = i;
      }
    }
    final bestDay = bestDayIndex >= 0 && s.output[bestDayIndex] > 0
        ? s.dates[bestDayIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: title, icon: icon, compact: singleModule),
        const SizedBox(height: 12),
        KpiRow(
          tiles: showRejection
              ? [
                  StatTile(
                    icon: Icons.factory_rounded,
                    accent: AppColors.steelBlue,
                    label: 'Total output',
                    value: _fmt(totalOutput),
                    unit: 'pcs',
                  ),
                  StatTile(
                    icon: Icons.report_gmailerrorred_rounded,
                    accent: AppColors.danger,
                    label: 'Total rejections',
                    value: _fmt(totalRejection),
                    unit: 'pcs',
                  ),
                  StatTile(
                    icon: Icons.percent_rounded,
                    accent: AppColors.danger,
                    label: 'Rejection rate',
                    value: rejectionRate == null
                        ? '—'
                        : rejectionRate.toStringAsFixed(1),
                    unit: rejectionRate == null ? null : '%',
                  ),
                  StatTile(
                    icon: Icons.speed_rounded,
                    accent: AppColors.amberDark,
                    label: 'Avg LOR',
                    value: avgLor == null ? '—' : avgLor.toStringAsFixed(1),
                    unit: avgLor == null ? null : '%',
                  ),
                ]
              : [
                  StatTile(
                    icon: Icons.factory_rounded,
                    accent: AppColors.steelBlue,
                    label: 'Total output',
                    value: _fmt(totalOutput),
                    unit: 'pcs',
                  ),
                  StatTile(
                    icon: Icons.speed_rounded,
                    accent: AppColors.amberDark,
                    label: 'Avg LOR',
                    value: avgLor == null ? '—' : avgLor.toStringAsFixed(1),
                    unit: avgLor == null ? null : '%',
                  ),
                  StatTile(
                    icon: Icons.emoji_events_rounded,
                    accent: AppColors.success,
                    label: 'Best day',
                    value: bestDay == null ? '—' : _fmt(s.output[bestDayIndex]),
                    unit: bestDay == null ? null : 'pcs',
                    helper: bestDay == null ? null : _shortDate(bestDay),
                  ),
                  StatTile(
                    icon: Icons.dashboard_rounded,
                    accent: AppColors.navy,
                    label: 'Reporting',
                    value: '${s.byGroup.length}',
                    unit: groupLabel,
                  ),
                ],
        ),
        const SizedBox(height: 14),
        TrendChart(
          title: 'Output',
          dates: s.dates,
          values: s.output,
          color: AppColors.steelBlue,
          suffix: '',
        ),
        const SizedBox(height: 14),
        TrendChart(
          title: 'LOR%',
          dates: s.dates,
          values: s.lorPercent,
          color: AppColors.amberDark,
          suffix: '%',
        ),
        if (showRejection) ...[
          const SizedBox(height: 14),
          TrendChart(
            title: 'Rejections',
            dates: s.dates,
            values: s.rejection,
            color: AppColors.danger,
            suffix: '',
          ),
        ],
        const SizedBox(height: 14),
        RankedBarChart(
          title: 'Output by $groupLabel',
          entries: [
            for (final g in s.byGroup)
              RankedBarEntry(
                label: g.group,
                value: g.output,
                sublabel: g.lorPercent == null
                    ? null
                    : 'LOR ${g.lorPercent!.toStringAsFixed(1)}%',
              ),
          ],
          color: AppColors.steelBlue,
        ),
        if (showRejection) ...[
          const SizedBox(height: 14),
          _RejectionBreakdown(types: s.rejectionsByType),
        ],
        const SizedBox(height: 14),
        InsightTable(
          title: 'Daily figures',
          columns: [
            const TableColumn('Date'),
            const TableColumn('Output', alignRight: true),
            const TableColumn('LOR%', alignRight: true),
            if (showRejection) const TableColumn('Rejects', alignRight: true),
          ],
          rows: [
            for (var i = s.dates.length - 1; i >= 0; i--)
              [
                _shortDate(s.dates[i]),
                _fmt(s.output[i]),
                s.lorPercent[i] == null
                    ? '—'
                    : '${s.lorPercent[i]!.toStringAsFixed(1)}%',
                if (showRejection) _fmt(s.rejection[i]),
              ],
          ],
        ),
      ],
    );
  }

  static String _shortDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    return '${parts[1]}/${parts[2]}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.icon,
    required this.compact,
  });

  final String title;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // A single-module (department-scoped) dashboard already says which
    // module this is via the tab/app-bar title, so the in-body header
    // shrinks rather than repeating it at full weight.
    if (compact) {
      return Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.amber),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Defect composition (donut, top 5 + Other) paired with the full ranking
/// (bar, same colors so a slice and its bar read as the same defect) and a
/// table underneath with the exact figures for every type that occurred.
class _RejectionBreakdown extends StatelessWidget {
  const _RejectionBreakdown({required this.types});

  final List<TypeTotal> types;

  static const _topN = 5;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.categoricalOf;
    final top = types.take(_topN).toList();
    final rest = types.skip(_topN).fold<double>(0, (a, b) => a + b.qty);

    final slices = <DonutSlice>[
      for (var i = 0; i < top.length; i++)
        DonutSlice(label: top[i].type, value: top[i].qty, color: palette[i]),
      if (rest > 0)
        DonutSlice(label: 'Other', value: rest, color: AppColors.textSecondary),
    ];

    return Column(
      children: [
        DonutChart(
          title: 'Defect composition',
          slices: slices,
          totalLabel: 'rejections',
        ),
        const SizedBox(height: 14),
        RankedBarChart(
          title: 'Defects by type',
          entries: [
            for (final t in types) RankedBarEntry(label: t.type, value: t.qty),
          ],
          color: AppColors.danger,
          colorForIndex: (i) => i < top.length ? palette[i] : AppColors.danger,
        ),
      ],
    );
  }
}
