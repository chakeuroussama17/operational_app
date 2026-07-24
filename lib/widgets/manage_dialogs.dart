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

enum ManageAction { rename, delete }

/// Bottom sheet with Rename/Delete actions for a long-pressed card. Returns
/// which action was picked, or null if dismissed.
Future<ManageAction?> showManageActionSheet(
  BuildContext context, {
  required String itemLabel,
}) {
  return showModalBottomSheet<ManageAction>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                itemLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppColors.steelBlue),
            title: const Text('Rename'),
            onTap: () => Navigator.of(sheetContext).pop(ManageAction.rename),
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
            ),
            title: const Text('Delete'),
            onTap: () => Navigator.of(sheetContext).pop(ManageAction.delete),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
