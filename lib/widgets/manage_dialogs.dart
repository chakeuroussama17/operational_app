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
  /// Everything in the dialog that is NOT the open list: title, the closed
  /// picker row, the MO field, the action row and the dialog's own margins.
  static const double _dialogChromeHeight = 340;

  final _searchController = TextEditingController();
  late final _moController = TextEditingController(
    text: widget.initialMo ?? '',
  );
  late String _selectedCode = widget.initialCode ?? '';

  /// The list is shut until the picker row is tapped, and shuts again the
  /// moment a code is chosen. Keeping it closed is what leaves room for the
  /// MO field below — an always-open list covered it.
  bool _open = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _moController.dispose();
    super.dispose();
  }

  /// The chosen entry, so the closed row can show its name as well as code.
  PartCode? get _selected {
    for (final c in widget.codes) {
      if (c.code == _selectedCode) return c;
    }
    return null;
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _error = null;
    });
    if (!_open) FocusScope.of(context).unfocus();
  }

  void _choose(PartCode option) {
    setState(() {
      _selectedCode = option.code;
      _error = null;
      _open = false; // close on pick, like a real dropdown
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _save() {
    if (_selectedCode.isEmpty) {
      setState(() {
        _error = 'Choose a part code';
        _open = true;
      });
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

    // Only matters while open: give the list whatever is left once the
    // keyboard and the rest of the dialog have taken their share.
    final media = MediaQuery.of(context);
    final room =
        media.size.height - media.viewInsets.bottom - _dialogChromeHeight;
    final listHeight = room.clamp(120.0, 260.0);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        // Roomy on a tablet/desktop, never wider than a phone screen.
        width: math.min(380, media.size.width * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PickerField(
              open: _open,
              selected: _selected,
              selectedCode: _selectedCode,
              error: _error,
              onTap: _toggle,
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search code or name',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
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
              SizedBox(
                height: listHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderSubtle),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
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
                        // No shrinkWrap: the box has a definite height, and
                        // shrinkWrap would lay out all ~230 rows on every
                        // keystroke instead of the visible handful.
                        : ListView.builder(
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
                                onTap: () => _choose(option),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _moController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'MO number (optional)',
                isDense: true,
              ),
              // Tapping into MO shuts the list, so the two never contend for
              // the same space.
              onTap: () {
                if (_open) setState(() => _open = false);
              },
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

/// The closed state of the part picker: what is chosen (or a prompt), and a
/// chevron that turns as the list opens.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.open,
    required this.selected,
    required this.selectedCode,
    required this.error,
    required this.onTap,
  });

  final bool open;
  final PartCode? selected;
  final String selectedCode;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final chosen = selectedCode.isNotEmpty;
    final name = selected?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasError
                    ? AppColors.danger
                    : open
                    ? AppColors.authViolet
                    : AppColors.borderSubtle,
                width: open || hasError ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tag_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chosen ? selectedCode : 'Choose part code',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: chosen
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: chosen
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (chosen && name != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              error!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
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
