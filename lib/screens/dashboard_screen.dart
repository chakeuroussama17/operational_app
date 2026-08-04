import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../services/sheets_service.dart';
import '../widgets/donut_chart.dart';
import '../widgets/error_retry.dart';
import '../widgets/filter_chip_row.dart';
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

/// Everything for one module, in the order a supervisor asks the questions:
/// where do we stand (KPIs), how are we trending (lines), day or night, who
/// is behind (ranking by machine/station/customer), what are we running
/// (ranking by part), what is failing (Machining's defect breakdown), and
/// the exact figures (tables).
///
/// The filter strip at the top scopes the trends and the part ranking to one
/// machine; the cross-group ranking stays, with the picked one emphasised so
/// you can see where it sits rather than losing the comparison.
class _ModuleSection extends StatefulWidget {
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
  /// "Customer") — names the filter, the ranking chart and its table column.
  final String groupLabel;
  final AnalyticsSeries? series;
  final bool showRejection;

  /// True when this is the only module shown (a department-scoped user) —
  /// the header shrinks since the tab title already says which module it is.
  final bool singleModule;

  @override
  State<_ModuleSection> createState() => _ModuleSectionState();
}

class _ModuleSectionState extends State<_ModuleSection> {
  /// null = every machine/station/customer.
  String? _group;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _shortDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    return '${parts[1]}/${parts[2]}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    if (s == null) {
      return _Header(
        title: widget.title,
        icon: widget.icon,
        compact: widget.singleModule,
      );
    }

    // A group that vanished from the data (the window changed under us)
    // falls back to "All" rather than charting nothing.
    final group = (_group != null && s.groupSeries.containsKey(_group))
        ? _group
        : null;

    // " — DCM 1212" on the charts the filter actually scopes, so a filtered
    // chart is never mistaken for a department-wide one sitting beside it.
    final scope = group == null ? '' : ' — ${widget.groupLabel} $group';

    final outputSeries = group == null
        ? s.output.map<double?>((v) => v).toList()
        : s.groupSeries[group]!.map<double?>((v) => v).toList();
    final lorSeries = group == null
        ? s.lorPercent
        : (s.groupLorSeries[group] ?? const <double?>[]);

    final totalOutput = outputSeries.fold<double>(0, (a, b) => a + (b ?? 0));
    final lorValues = lorSeries.whereType<double>();
    final avgLor = lorValues.isEmpty
        ? null
        : lorValues.fold<double>(0, (a, b) => a + b) / lorValues.length;

    final parts = s.partsFor(group);
    final totalRejection = group == null
        ? s.rejection.fold<double>(0, (a, b) => a + b)
        : parts.fold<double>(0, (a, p) => a + p.rejection);
    final rejectionRate = (totalOutput + totalRejection) > 0
        ? totalRejection / (totalOutput + totalRejection) * 100
        : null;

    var bestDayIndex = -1;
    for (var i = 0; i < outputSeries.length; i++) {
      final v = outputSeries[i] ?? 0;
      if (bestDayIndex == -1 || v > (outputSeries[bestDayIndex] ?? 0)) {
        bestDayIndex = i;
      }
    }
    final bestDay = bestDayIndex >= 0 && (outputSeries[bestDayIndex] ?? 0) > 0
        ? s.dates[bestDayIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: widget.title,
          icon: widget.icon,
          compact: widget.singleModule,
        ),
        if (s.groupNames.length > 1) ...[
          const SizedBox(height: 12),
          FilterChipRow(
            label: widget.groupLabel.toUpperCase(),
            options: s.groupNames,
            selected: group,
            onSelected: (value) => setState(() => _group = value),
          ),
        ],
        const SizedBox(height: 12),
        KpiRow(
          tiles: widget.showRejection
              ? [
                  StatTile(
                    icon: Icons.factory_rounded,
                    accent: AppColors.steelBlue,
                    label: 'Total output',
                    value: _fmt(totalOutput),
                    unit: 'pcs',
                    helper: group == null
                        ? null
                        : '${widget.groupLabel} $group',
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
                    helper: group == null
                        ? null
                        : '${widget.groupLabel} $group',
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
                    value: bestDay == null
                        ? '—'
                        : _fmt(outputSeries[bestDayIndex] ?? 0),
                    unit: bestDay == null ? null : 'pcs',
                    helper: bestDay == null ? null : _shortDate(bestDay),
                  ),
                  StatTile(
                    icon: Icons.inventory_2_rounded,
                    accent: AppColors.navy,
                    label: 'Parts running',
                    value: '${parts.length}',
                    unit: parts.length == 1 ? 'part' : 'parts',
                  ),
                ],
        ),
        const SizedBox(height: 14),
        TrendChart.single(
          title: 'Output$scope',
          dates: s.dates,
          values: outputSeries,
          color: AppColors.steelBlue,
        ),
        const SizedBox(height: 14),
        TrendChart.single(
          title: 'LOR%$scope',
          dates: s.dates,
          values: lorSeries,
          color: AppColors.amberDark,
          suffix: '%',
        ),
        if (widget.showRejection && group == null) ...[
          const SizedBox(height: 14),
          TrendChart.single(
            title: 'Rejections',
            dates: s.dates,
            values: s.rejection.map<double?>((v) => v).toList(),
            color: AppColors.danger,
          ),
        ],
        // Day vs Night is a department-level question and the backend splits
        // it that way, so it stays whole rather than pretending to follow
        // the machine filter.
        if (s.byShift.length == 2) ...[
          const SizedBox(height: 14),
          _ShiftComparison(series: s),
        ],
        const SizedBox(height: 14),
        RankedBarChart(
          title: 'Output by ${widget.groupLabel}',
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
          // Emphasis: with one picked it keeps the hue and the rest recede,
          // so the comparison survives the filter instead of disappearing.
          colorForIndex: group == null
              ? null
              : (i) => s.byGroup[i].group == group
                    ? AppColors.steelBlue
                    : AppColors.chartMuted,
        ),
        const SizedBox(height: 14),
        RankedBarChart(
          title: 'Output by part$scope',
          entries: [
            for (final p in parts.take(10))
              RankedBarEntry(
                label: p.part,
                value: p.output,
                sublabel: p.name.isEmpty ? null : p.name,
              ),
          ],
          color: AppColors.navy,
        ),
        if (widget.showRejection) ...[
          if (group == null) ...[
            const SizedBox(height: 14),
            _RejectionBreakdown(types: s.rejectionsByType),
          ],
          const SizedBox(height: 14),
          _RejectionsByPart(parts: parts, scope: scope),
        ],
        const SizedBox(height: 14),
        InsightTable(
          title: 'Daily figures$scope',
          columns: [
            const TableColumn('Date'),
            const TableColumn('Output', alignRight: true),
            const TableColumn('LOR%', alignRight: true),
            if (widget.showRejection && group == null)
              const TableColumn('Rejects', alignRight: true),
          ],
          rows: [
            for (var i = s.dates.length - 1; i >= 0; i--)
              [
                _shortDate(s.dates[i]),
                _fmt(i < outputSeries.length ? (outputSeries[i] ?? 0) : 0),
                i < lorSeries.length && lorSeries[i] != null
                    ? '${lorSeries[i]!.toStringAsFixed(1)}%'
                    : '—',
                if (widget.showRejection && group == null)
                  _fmt(i < s.rejection.length ? s.rejection[i] : 0),
              ],
          ],
        ),
        const SizedBox(height: 14),
        InsightTable(
          title: 'Parts$scope',
          columns: [
            const TableColumn('Part'),
            if (group == null) TableColumn(widget.groupLabel),
            const TableColumn('Output', alignRight: true),
            if (widget.showRejection)
              const TableColumn('Rejects', alignRight: true),
            if (widget.showRejection)
              const TableColumn('Rate', alignRight: true),
          ],
          rows: [
            for (final p in parts)
              [
                p.label,
                if (group == null) p.groupLabelWith(widget.groupLabel),
                _fmt(p.output),
                if (widget.showRejection) _fmt(p.rejection),
                if (widget.showRejection)
                  p.rejectRate == null
                      ? '—'
                      : '${p.rejectRate!.toStringAsFixed(1)}%',
              ],
          ],
        ),
      ],
    );
  }
}

/// Day vs Night: the window totals as headline numbers, and the same split
/// per day so "which shift is ahead" and "is the gap widening" are both
/// answerable. Two series, one shared axis, always with a legend.
class _ShiftComparison extends StatelessWidget {
  const _ShiftComparison({required this.series});

  final AnalyticsSeries series;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final day = series.byShift.firstWhere(
      (s) => s.shift == 'Day',
      orElse: () => const ShiftTotal(shift: 'Day', output: 0),
    );
    final night = series.byShift.firstWhere(
      (s) => s.shift == 'Night',
      orElse: () => const ShiftTotal(shift: 'Night', output: 0),
    );
    final total = day.output + night.output;
    final dayShare = total > 0 ? day.output / total * 100 : null;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.cardRadius),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Day vs Night',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ShiftStat(
                      icon: Icons.wb_sunny_rounded,
                      label: 'Day',
                      output: _fmt(day.output),
                      lor: day.lorPercent,
                      color: AppColors.amberDark,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 46,
                    color: AppColors.borderSubtle,
                  ),
                  Expanded(
                    child: _ShiftStat(
                      icon: Icons.nightlight_round,
                      label: 'Night',
                      output: _fmt(night.output),
                      lor: night.lorPercent,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
              if (dayShare != null) ...[
                const SizedBox(height: 14),
                _ShiftSplitBar(dayShare: dayShare),
                const SizedBox(height: 6),
                Text(
                  day.output >= night.output
                      ? 'Day carries ${dayShare.toStringAsFixed(0)}% of output'
                      : 'Night carries ${(100 - dayShare).toStringAsFixed(0)}% of output',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TrendChart(
          title: 'Output per shift',
          dates: series.dates,
          series: [
            TrendSeries(
              name: 'Day',
              values: (series.shiftSeries['Day'] ?? const <double>[])
                  .map<double?>((v) => v)
                  .toList(),
              color: AppColors.amberDark,
            ),
            TrendSeries(
              name: 'Night',
              values: (series.shiftSeries['Night'] ?? const <double>[])
                  .map<double?>((v) => v)
                  .toList(),
              color: AppColors.navy,
            ),
          ],
        ),
      ],
    );
  }
}

class _ShiftStat extends StatelessWidget {
  const _ShiftStat({
    required this.icon,
    required this.label,
    required this.output,
    required this.lor,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String output;
  final double? lor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          output,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          lor == null ? '—' : 'LOR ${lor!.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A single part-to-whole bar for the two shifts — two categories is a bar's
/// job, never a pie's. A 2px surface gap does the separating.
class _ShiftSplitBar extends StatelessWidget {
  const _ShiftSplitBar({required this.dayShare});

  final double dayShare;

  @override
  Widget build(BuildContext context) {
    final day = (dayShare / 100).clamp(0.0, 1.0);
    return SizedBox(
      height: 10,
      child: Row(
        children: [
          if (day > 0)
            Expanded(
              flex: (day * 1000).round(),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.amberDark,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(5),
                    right: Radius.circular(2),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 2),
          if (day < 1)
            Expanded(
              flex: ((1 - day) * 1000).round(),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(2),
                    right: Radius.circular(5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Which parts are throwing the scrap — by count, and by RATE. Count alone
/// misleads: a part that ran 5,000 and scrapped 60 is healthier than one
/// that ran 80 and scrapped 40, and only the rate says so.
class _RejectionsByPart extends StatelessWidget {
  const _RejectionsByPart({required this.parts, required this.scope});

  final List<PartTotal> parts;
  final String scope;

  /// A rate needs enough pieces behind it to mean anything — one reject out
  /// of two is 50% and tells you nothing.
  static const _minPiecesForRate = 20;

  @override
  Widget build(BuildContext context) {
    final offenders = [
      for (final p in parts)
        if (p.rejection > 0) p,
    ]..sort((a, b) => b.rejection.compareTo(a.rejection));

    final byRate = [
      for (final p in offenders)
        if ((p.output + p.rejection) >= _minPiecesForRate) p,
    ]..sort((a, b) => (b.rejectRate ?? 0).compareTo(a.rejectRate ?? 0));

    return Column(
      children: [
        RankedBarChart(
          title: 'Rejections by part$scope',
          entries: [
            for (final p in offenders.take(10))
              RankedBarEntry(
                label: p.part,
                value: p.rejection,
                sublabel: p.rejectRate == null
                    ? null
                    : '${p.rejectRate!.toStringAsFixed(1)}% of '
                          '${(p.output + p.rejection).round()}',
              ),
          ],
          color: AppColors.danger,
          emptyMessage: 'No rejections logged in this window',
        ),
        if (byRate.isNotEmpty) ...[
          const SizedBox(height: 14),
          RankedBarChart(
            title: 'Worst rejection rate$scope',
            entries: [
              for (final p in byRate.take(10))
                RankedBarEntry(
                  label: p.part,
                  value: p.rejectRate ?? 0,
                  sublabel:
                      '${p.rejection.round()} of '
                      '${(p.output + p.rejection).round()}',
                ),
            ],
            color: AppColors.danger,
            suffix: '%',
          ),
        ],
      ],
    );
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
/// (bar, same colors so a slice and its bar read as the same defect).
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
