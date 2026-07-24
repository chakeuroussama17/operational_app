import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../services/sheets_service.dart';
import '../widgets/error_retry.dart';
import '../widgets/trend_chart.dart';

/// Real-time analytics tab: daily output/LOR%/rejection trend charts for
/// each module, pulled live from the sheet. Independent of the Log tab —
/// this never writes anything, only reads.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  int _days = 14;
  AnalyticsSeries? _casting;
  AnalyticsSeries? _secondary;
  AnalyticsSeries? _machining;

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
      final results = await Future.wait([
        _sheetsService.fetchAnalytics(module: 'casting', days: _days),
        _sheetsService.fetchAnalytics(module: 'secondary', days: _days),
        _sheetsService.fetchAnalytics(module: 'machining', days: _days),
      ]);
      if (!mounted) return;
      setState(() {
        _casting = results[0];
        _secondary = results[1];
        _machining = results[2];
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
          _ModuleSection(
            title: 'Casting',
            icon: Icons.local_fire_department_rounded,
            series: _casting,
          ),
          const SizedBox(height: 22),
          _ModuleSection(
            title: 'Secondary',
            icon: Icons.handyman_rounded,
            series: _secondary,
          ),
          const SizedBox(height: 22),
          _ModuleSection(
            title: 'Machining',
            icon: Icons.precision_manufacturing_rounded,
            series: _machining,
            showRejection: true,
          ),
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
