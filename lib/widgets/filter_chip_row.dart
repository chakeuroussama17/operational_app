import 'package:flutter/material.dart';

import '../config/constants.dart';

/// A single-select filter strip: "All" plus one chip per option, scrolling
/// horizontally when there are more than fit.
///
/// Deliberately sits ABOVE everything it scopes rather than inside a chart
/// card — one filter, one slice, every chart below it re-reads the same
/// selection. Selecting is instant: the data for every option is already
/// fetched, so nothing round-trips.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allLabel = 'All',
  });

  /// What the options are ("DCM", "Station", "Customer") — names the strip.
  final String label;
  final List<String> options;

  /// null means "All".
  final String? selected;
  final ValueChanged<String?> onSelected;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    if (options.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.filter_alt_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: options.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              if (i == 0) {
                return _Chip(
                  label: allLabel,
                  selected: selected == null,
                  onTap: () => onSelected(null),
                );
              }
              final option = options[i - 1];
              return _Chip(
                label: option,
                selected: selected == option,
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
