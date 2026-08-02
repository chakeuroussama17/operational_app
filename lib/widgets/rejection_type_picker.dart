import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/rejection.dart';

/// Searchable picker for the rejection-code master.
///
/// A plain dropdown would be unusable — the master runs to ~230 defect types —
/// so this is a search box over an inline list, matching on either the code or
/// the name ("064", "poros", "blow").
Future<RejectionType?> promptRejectionType(
  BuildContext context, {
  required List<RejectionType> types,
  String? initialCode,
}) {
  return showDialog<RejectionType>(
    context: context,
    builder: (_) =>
        _RejectionTypeDialog(types: types, initialCode: initialCode),
  );
}

/// Stateful so the search controller lives exactly as long as the dialog's
/// ROUTE, not the `showDialog` future: the exit animation still rebuilds the
/// search field after the future completes, so disposing the controller at
/// that point crashes the closing dialog.
class _RejectionTypeDialog extends StatefulWidget {
  const _RejectionTypeDialog({required this.types, this.initialCode});

  final List<RejectionType> types;
  final String? initialCode;

  @override
  State<_RejectionTypeDialog> createState() => _RejectionTypeDialogState();
}

class _RejectionTypeDialogState extends State<_RejectionTypeDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.types
        : widget.types
              .where(
                (t) =>
                    t.code.toLowerCase().contains(query) ||
                    t.type.toLowerCase().contains(query),
              )
              .toList();

    return AlertDialog(
      title: const Text('Rejection type'),
      content: SizedBox(
        width: math.min(420, MediaQuery.of(context).size.width * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search code or defect',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              '${matches.length} of ${widget.types.length} types',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No defect matches that search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final option = matches[i];
                        final isSelected = option.code == widget.initialCode;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: AppColors.surfaceTint,
                          leading: Text(
                            option.code,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          title: Text(
                            option.type,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.success,
                                  size: 20,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
      ],
    );
  }
}
