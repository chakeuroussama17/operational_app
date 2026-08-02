import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/part_code.dart';

// NOTE on dialog controllers: every dialog here is a StatefulWidget that owns
// its TextEditingControllers and disposes them in its own dispose(). Disposing
// right after `await showDialog(...)` returns is a crash: the route's exit
// animation still rebuilds the fields for a few frames after the future
// completes (the rejection-type picker hit exactly this).

/// Small text-entry dialog used for adding/renaming groups, parts and lines.
/// Returns the trimmed text, or null if cancelled/left empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _PromptTextDialog(
      title: title,
      label: label,
      initialValue: initialValue,
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}

class _PromptTextDialog extends StatefulWidget {
  const _PromptTextDialog({
    required this.title,
    required this.label,
    this.initialValue,
  });

  final String title;
  final String label;
  final String? initialValue;

  @override
  State<_PromptTextDialog> createState() => _PromptTextDialogState();
}

class _PromptTextDialogState extends State<_PromptTextDialog> {
  late final _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('SAVE'),
        ),
      ],
    );
  }
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
  required String moduleLabel,
  List<PartCode> codes = const [],
  String? initialCode,
  String? initialMo,
}) {
  return showDialog<PartWithMoInput>(
    context: context,
    builder: (_) => _PartCodeDialog(
      title: title,
      moduleLabel: moduleLabel,
      codes: codes,
      initialCode: initialCode,
      initialMo: initialMo,
    ),
  );
}

class _PartCodeDialog extends StatefulWidget {
  const _PartCodeDialog({
    required this.title,
    required this.moduleLabel,
    required this.codes,
    this.initialCode,
    this.initialMo,
  });

  final String title;
  final String moduleLabel;
  final List<PartCode> codes;
  final String? initialCode;
  final String? initialMo;

  @override
  State<_PartCodeDialog> createState() => _PartCodeDialogState();
}

class _PartCodeDialogState extends State<_PartCodeDialog> {
  final _searchController = TextEditingController();
  late final _moController = TextEditingController(
    text: widget.initialMo ?? '',
  );
  late String _selectedCode = widget.initialCode ?? '';
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _moController.dispose();
    super.dispose();
  }

  void _save() {
    if (_selectedCode.isEmpty) {
      setState(() => _error = 'Choose a part code');
      return;
    }
    Navigator.of(
      context,
    ).pop(PartWithMoInput(name: _selectedCode, mo: _moController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.codes
        : widget.codes
              .where(
                (c) =>
                    c.code.toLowerCase().contains(query) ||
                    (c.name ?? '').toLowerCase().contains(query),
              )
              .toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        // Roomy on a tablet/desktop, never wider than a phone screen.
        width: math.min(380, MediaQuery.of(context).size.width * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Search part code or name',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 8),
            // The same code exists in several departments (a part is cast,
            // then fettled, then machined), so spell out that this list is
            // only this module's operations.
            Text(
              '${matches.length} of ${widget.codes.length} '
              '${widget.moduleLabel} parts',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
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
                        widget.codes.isEmpty
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
                        final isSelected = option.code == _selectedCode;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: AppColors.surfaceTint,
                          title: Text(
                            option.code,
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
                            _selectedCode = option.code;
                            _error = null;
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _moController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'MO number (optional)',
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_selectedCode.isEmpty ? 'SAVE' : 'SAVE $_selectedCode'),
        ),
      ],
    );
  }
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
