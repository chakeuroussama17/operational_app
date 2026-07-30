import 'package:flutter/material.dart';

import '../config/constants.dart';

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

/// Add/edit dialog for a part. On ADD, the part code is chosen from [codes]
/// (the module's master list) via a type-to-search field — no free typing of
/// new codes. On EDIT ([lockCode] = true) the code is fixed and only the MO
/// can change. Returns null if cancelled or no code was chosen.
Future<PartWithMoInput?> promptPartCode(
  BuildContext context, {
  required String title,
  List<String> codes = const [],
  String? initialCode,
  String? initialMo,
  bool lockCode = false,
}) async {
  final moController = TextEditingController(text: initialMo ?? '');
  var selectedCode = initialCode ?? '';
  String? error;

  final result = await showDialog<PartWithMoInput>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        void save() {
          final code = selectedCode.trim();
          if (code.isEmpty) {
            setState(() => error = 'Choose a part code');
            return;
          }
          if (!lockCode && codes.isNotEmpty && !codes.contains(code)) {
            setState(() => error = 'Pick a code from the list');
            return;
          }
          Navigator.of(
            dialogContext,
          ).pop(PartWithMoInput(name: code, mo: moController.text.trim()));
        }

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lockCode)
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Part code'),
                  child: Text(
                    selectedCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Autocomplete<String>(
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return codes;
                    return codes.where((c) => c.toLowerCase().contains(q));
                  },
                  onSelected: (c) => setState(() {
                    selectedCode = c;
                    error = null;
                  }),
                  fieldViewBuilder:
                      (ctx, textController, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: textController,
                          focusNode: focusNode,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Part code',
                            helperText: 'Type to search · choose from the list',
                            errorText: error,
                          ),
                          onChanged: (v) => selectedCode = v,
                        );
                      },
                ),
              const SizedBox(height: 14),
              TextField(
                controller: moController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'MO number (optional)',
                  helperText: 'Manufacturing order — update monthly',
                ),
                onSubmitted: (_) => save(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(onPressed: save, child: const Text('SAVE')),
          ],
        );
      },
    ),
  );
  moController.dispose();
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
