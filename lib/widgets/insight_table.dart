import 'package:flutter/material.dart';

import '../config/constants.dart';

/// One column of an [InsightTable]: a header label and how its cells align.
class TableColumn {
  const TableColumn(this.label, {this.alignRight = false});

  final String label;
  final bool alignRight;
}

/// The table-view twin every chart on this dashboard has a companion for —
/// the WCAG-clean equivalent that never gates a value behind a tooltip or a
/// color. A sticky header, alternating row tint for scanability, and
/// tabular figures so the columns actually line up (reserved for exactly
/// this — a large standalone number elsewhere uses proportional figures).
class InsightTable extends StatelessWidget {
  const InsightTable({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.maxHeight = 280,
    this.emptyMessage = 'No data logged yet in this window',
  });

  final String title;
  final List<TableColumn> columns;

  /// One string per cell, same order as [columns].
  final List<List<String>> rows;
  final double maxHeight;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.table_rows_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else ...[
            _HeaderRow(columns: columns),
            Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      _DataRow(
                        columns: columns,
                        cells: rows[i],
                        tinted: i.isOdd,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final List<TableColumn> columns;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (final col in columns)
            Expanded(
              child: Text(
                col.label,
                textAlign: col.alignRight ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.columns,
    required this.cells,
    required this.tinted,
  });

  final List<TableColumn> columns;
  final List<String> cells;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tinted ? AppColors.surfaceTint.withValues(alpha: 0.5) : null,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              child: Text(
                i < cells.length ? cells[i] : '',
                textAlign: columns[i].alignRight
                    ? TextAlign.right
                    : TextAlign.left,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
