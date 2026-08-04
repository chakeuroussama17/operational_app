import 'package:flutter/material.dart';

import '../config/constants.dart';

/// One headline number: "the data's job is a single current value" gets a
/// stat tile, not a one-bar chart. A horizontally-scrolling strip of these
/// (see [KpiRow]) is the "handful of headline numbers" form — never a chart
/// for what a number already says outright.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.unit,
    this.helper,
  });

  final IconData icon;
  final Color accent;

  /// Sentence case, no trailing colon.
  final String label;

  /// Pre-formatted, e.g. "1,284" or "83.3". Proportional figures — this is a
  /// display-size number, not a table column, so no tabular-nums.
  final String value;

  /// Appended right after the value in a smaller weight, e.g. "%" or "pcs".
  final String? unit;

  /// A short second line under the value — a date, a count, extra context.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A horizontally-scrolling strip of [StatTile]s — never wraps or shrinks
/// tiles to fit, so a headline number is never squeezed illegible on a
/// narrow phone.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 136,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}
