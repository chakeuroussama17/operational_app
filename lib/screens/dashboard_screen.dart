import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../services/sheets_service.dart';
import '../widgets/error_retry.dart';
import '../widgets/trend_chart.dart';

/// Real-time analytics tab: daily output/LOR%/rejection trend charts, pulled
/// live from the sheet. Independent of the Log tab — this never writes
/// anything, only reads.
///
/// Shows one section per module the signed-in person's department covers, so
/// a casting supervisor watches casting alone and the admin sees all three.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.modules});

  /// Lowercase module keys to chart, in display order. Null means all three
  /// (widget tests, which pump this without a signed-in user).
  final List<String>? modules;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _sheetsService = SheetsService();

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
      });
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
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

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.steelBlue),
      );
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      color: AppColors.steelBlue,
      onRefresh: _load,
      child: ListView(
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
              series: _series[module],
              showRejection: module == 'machining',
            ),
            const SizedBox(height: 22),
          ],
          const SizedBox(height: 12),
        ],
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
            color: selected ? Colors.white : AppColors.steelBlue,
          ),
        ),
      ),
    );
  }
}

class _ModuleSection extends StatelessWidget {
  const _ModuleSection({
    required this.title,
    required this.icon,
    required this.series,
    this.showRejection = false,
  });

  final String title;
  final IconData icon;
  final AnalyticsSeries? series;
  final bool showRejection;

  @override
  Widget build(BuildContext context) {
    final s = series;
    if (s == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TrendChart(
          title: 'Total output / day',
          dates: s.dates,
          values: s.output,
          color: AppColors.steelBlue,
        ),
        const SizedBox(height: 10),
        TrendChart(
          title: 'Average LOR% / day',
          dates: s.dates,
          values: s.lorPercent,
          color: AppColors.amber,
          suffix: '%',
        ),
        if (showRejection && s.rejection.isNotEmpty) ...[
          const SizedBox(height: 10),
          TrendChart(
            title: 'Total rejection / day',
            dates: s.dates,
            values: s.rejection,
            color: AppColors.danger,
          ),
        ],
      ],
    );
  }
}
