import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/part_code.dart';

/// Small text-entry dialog used for adding/renaming groups, parts and lines.
/// Returns the trimmed text, or null if cancelled/left empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('SAVE'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (result == null || result.isEmpty) ? null : result;
}

/// Result of [promptPartCode]: [name] holds the chosen part CODE (from the
/// master list), plus its MO (manufacturing order) number.
class PartWithMoInput {
  const PartWithMoInput({required this.name, required this.mo});

  /// The chosen part code.
  final String name;

  /// '' if left blank (no MO set / clearing an existing one).
  final String mo;
}

/// Add/edit dialog for a part. The part code is picked from [codes] (the
/// module's slice of the master list) — a search box filtering an inline list
/// of code + name, so nothing can be typed that isn't a real code. On edit,
/// [initialCode] starts selected and can be changed (the backend re-resolves
/// the barcode/name for the new code). Returns null if cancelled.
///
/// The list is inline rather than an [Autocomplete] overlay: inside a dialog
/// the floating options box is clipped/mispositioned, and an inline list has
/// room to show each code's part name.
Future<PartWithMoInput?> promptPartCode(
  BuildContext context, {
  required String title,
  List<PartCode> codes = const [],
  String? initialCode,
  String? initialMo,
}) async {
  final moController = TextEditingController(text: initialMo ?? '');
  final searchController = TextEditingController();
  var selectedCode = initialCode ?? '';
  String? error;

  final result = await showDialog<PartWithMoInput>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final query = searchController.text.trim().toLowerCase();
        final matches = query.isEmpty
            ? codes
            : codes
                  .where(
                    (c) =>
                        c.code.toLowerCase().contains(query) ||
                        (c.name ?? '').toLowerCase().contains(query),
                  )
                  .toList();

        void save() {
          if (selectedCode.isEmpty) {
            setState(() => error = 'Choose a part code');
            return;
          }
          Navigator.of(dialogContext).pop(
            PartWithMoInput(name: selectedCode, mo: moController.text.trim()),
          );
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            // Roomy on a tablet/desktop, never wider than a phone screen.
            width: math.min(
              380,
              MediaQuery.of(dialogContext).size.width * 0.86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Search part code or name',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    errorText: error,
                  ),
                  onChanged: (_) => setState(() => error = null),
                ),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderSubtle),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: matches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            codes.isEmpty
                                ? 'No part codes for this module.'
                                : 'No code or name matches that search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: matches.length,
                          itemBuilder: (context, i) {
                            final option = matches[i];
                            final isSelected = option.code == selectedCode;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: AppColors.surfaceTint,
                              title: Text(
                                option.code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: option.name == null
                                  ? null
                                  : Text(
                                      option.name!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: AppColors.success,
                                      size: 20,
                                    )
                                  : null,
                              onTap: () => setState(() {
                                selectedCode = option.code;
                                error = null;
                              }),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: moController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'MO number (optional)',
                    isDense: true,
                  ),
                  onSubmitted: (_) => save(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: save,
              child: Text(selectedCode.isEmpty ? 'SAVE' : 'SAVE $selectedCode'),
            ),
          ],
        );
      },
    ),
  );
  moController.dispose();
  searchController.dispose();
  return result;
}

/// Confirmation dialog for a destructive delete. Returns true if confirmed.
Future<bool?> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('DELETE'),
        ),
      ],
    ),
  );
}
