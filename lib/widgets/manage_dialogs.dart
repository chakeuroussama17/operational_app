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

/// Result of [promptCastingPart]: the part name plus its MO (manufacturing
/// order) number — Casting parts are the only ones with an MO field.
class CastingPartInput {
  const CastingPartInput({required this.name, required this.mo});

  final String name;

  /// '' if left blank (no MO set / clearing an existing one).
  final String mo;
}

/// Add/edit dialog for a Casting part: name plus its MO number. Returns null
/// if cancelled or the name was left empty.
Future<CastingPartInput?> promptCastingPart(
  BuildContext context, {
  required String title,
  String? initialName,
  String? initialMo,
}) async {
  final nameController = TextEditingController(text: initialName ?? '');
  final moController = TextEditingController(text: initialMo ?? '');
  final result = await showDialog<CastingPartInput>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Part'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: moController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'MO number (optional)',
              helperText: 'Manufacturing order — update monthly',
            ),
            onSubmitted: (_) => Navigator.of(dialogContext).pop(
              CastingPartInput(
                name: nameController.text.trim(),
                mo: moController.text.trim(),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            CastingPartInput(
              name: nameController.text.trim(),
              mo: moController.text.trim(),
            ),
          ),
          child: const Text('SAVE'),
        ),
      ],
    ),
  );
  nameController.dispose();
  moController.dispose();
  if (result == null || result.name.isEmpty) return null;
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
