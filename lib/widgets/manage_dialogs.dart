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

/// Single-select picker over a fixed list of names — the casting machines.
///
/// Free text let the same machine into the sheet under several spellings
/// ("DCM8", "dcm 08"), and every one of those is a separate group that splits
/// its own history. Picking from a list makes that impossible.
///
/// [taken] are names already configured: shown, but greyed and unselectable,
/// so it's obvious the machine exists rather than the list being wrong.
/// [initialValue] is always selectable even when taken (that's the row being
/// renamed) and is shown even when it isn't in [options] at all — which is how
/// a legacy name like "1212" can be moved onto a real one.
///
/// Returns the chosen name, or null if dismissed.
Future<String?> promptFromList(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? initialValue,
  Set<String> taken = const {},
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ListPickerDialog(
      title: title,
      options: options,
      initialValue: initialValue,
      taken: taken,
    ),
  );
}

class _ListPickerDialog extends StatelessWidget {
  const _ListPickerDialog({
    required this.title,
    required this.options,
    required this.initialValue,
    required this.taken,
  });

  final String title;
  final List<String> options;
  final String? initialValue;
  final Set<String> taken;

  @override
  Widget build(BuildContext context) {
    final current = initialValue;
    // A name being renamed that predates this list still needs a row to sit
    // on, otherwise the dialog opens with nothing selected and no way to see
    // what is being changed.
    final entries = [
      if (current != null && current.isNotEmpty && !options.contains(current))
        current,
      ...options,
    ];

    final media = MediaQuery.of(context);
    final listHeight = (media.size.height - 260).clamp(160.0, 380.0);

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: math.min(380, media.size.width * 0.86),
        height: listHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final name = entries[i];
                final isSelected = name == current;
                final isTaken = taken.contains(name) && !isSelected;
                return ListTile(
                  dense: true,
                  enabled: !isTaken,
                  selected: isSelected,
                  selectedTileColor: AppColors.surfaceTint,
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isTaken
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: isTaken
                      ? Text(
                          'Already added',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : null,
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                          size: 20,
                        )
                      : null,
                  onTap: isTaken
                      ? null
                      : () => Navigator.of(context).pop(name),
                );
              },
            ),
          ),
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

/// Add/edit dialog for a part. The part code is picked from [codes] (the
/// module's slice of the master list) — a search box filtering an inline list
/// of code + name. When the search matches nothing the typed text can be used
/// as the code anyway: the Parts master is not always complete or up to date,
/// and a supervisor who can see the part in front of them should not be
/// blocked from logging it. Such a code carries no barcode/name to snapshot,
/// so the dialog says so before it is accepted. On edit, [initialCode] starts
/// selected and can be changed (the backend re-resolves the barcode/name for
/// the new code). Returns null if cancelled.
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
  /// picker row, the search box, the count line, the MO field, the action row,
  /// and AlertDialog's own inset padding.
  ///
  /// Measured, not estimated: at 340 the dialog overflowed a 600px-tall
  /// viewport by 74px with the list at its 260 maximum. Only short screens
  /// feel this number — anywhere taller, `room` exceeds the 260 cap anyway.
  static const double _dialogChromeHeight = 420;

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

  /// A code the user typed rather than picked. It has no master row behind it,
  /// so the picker row flags it instead of showing a part name.
  bool get _isManual => _selectedCode.isNotEmpty && _selected == null;

  /// Takes the search text as the code. Same closing behaviour as picking from
  /// the list, so the two paths feel identical.
  void _useTyped(String typed) {
    setState(() {
      _selectedCode = typed;
      _error = null;
      _open = false;
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
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
        _error = 'Pick a part code, or type one in';
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
    final typed = _searchController.text.trim();
    final query = typed.toLowerCase();
    final matches = query.isEmpty
        ? widget.codes
        : widget.codes
              .where(
                (c) =>
                    c.code.toLowerCase().contains(query) ||
                    (c.name ?? '').toLowerCase().contains(query),
              )
              .toList();

    // Offer the typed text as a code once it is worth offering: there IS
    // something typed, and it isn't already a code in the list (in which case
    // the user should pick that row rather than duplicate it).
    final canUseTyped =
        typed.isNotEmpty &&
        !widget.codes.any((c) => c.code.toLowerCase() == query);

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
              manual: _isManual,
              error: _error,
              onTap: _toggle,
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search, or type a code that is missing',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              // The same code exists in several departments (a part is cast,
              // then fettled, then machined), and Machining narrows further
              // still to one operation's half of the master — so name the
              // slice rather than leaving the count unexplained.
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
                        ? (canUseTyped
                              ? _UseTypedTile(
                                  typed: typed,
                                  onTap: () => _useTyped(typed),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    widget.codes.isEmpty
                                        ? 'No part codes for this module.'
                                        : 'Type the part code to add one that '
                                              'is not on the list.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ))
                        // No shrinkWrap: the box has a definite height, and
                        // shrinkWrap would lay out all ~230 rows on every
                        // keystroke instead of the visible handful.
                        : ListView.builder(
                            itemCount: matches.length + (canUseTyped ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == matches.length) {
                                return _UseTypedTile(
                                  typed: typed,
                                  onTap: () => _useTyped(typed),
                                );
                              }
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
    required this.manual,
    required this.error,
    required this.onTap,
  });

  final bool open;
  final PartCode? selected;
  final String selectedCode;

  /// True when the code was typed rather than picked — shown explicitly, since
  /// it means no barcode or part name gets snapshotted onto the logged rows.
  final bool manual;
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
                      ] else if (manual) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Typed in — not on the parts list',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.amberDark,
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

/// The escape hatch at the bottom of the part list: use exactly what was typed
/// as the code. Deliberately styled apart from the real rows (amber, dashed
/// intent) so nobody takes it for a master entry they found.
class _UseTypedTile extends StatelessWidget {
  const _UseTypedTile({required this.typed, required this.onTap});

  final String typed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: const Icon(
        Icons.edit_note_rounded,
        color: AppColors.amberDark,
        size: 22,
      ),
      title: Text(
        'Use "$typed"',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.amberDark,
        ),
      ),
      subtitle: Text(
        'Not on the list — logs under this code with no part name',
        maxLines: 2,
        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
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
