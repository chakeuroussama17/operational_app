import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../models/rejection.dart';
import '../services/sheets_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/rejection_type_picker.dart';
import '../widgets/submission_feedback.dart';
import '../widgets/submit_button.dart';

/// Data entry for one Customer + Part + Line + Shift. Pre-fills this shift's
/// saved values, lets the supervisor fill any subset of time slots, and
/// submits only the fields that changed — the backend upserts and
/// recalculates LOR%.
class MachiningEntryScreen extends StatefulWidget {
  const MachiningEntryScreen({
    super.key,
    required this.customer,
    required this.part,
    required this.line,
    required this.shift,
    this.mo,
    this.service,
  });

  final String customer;
  final String part;
  final String line;
  final String shift;

  /// The part's MO (manufacturing order) number — shown as read-only context.
  /// Edit it from the part's Edit action on the Parts screen.
  final String? mo;

  /// Test seam: the screen normally builds its own [SheetsService] against the
  /// real backend; widget tests inject one backed by a mock client instead.
  final SheetsService? service;

  @override
  State<MachiningEntryScreen> createState() => _MachiningEntryScreenState();
}

class _MachiningEntryScreenState extends State<MachiningEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _sheetsService = widget.service ?? SheetsService();

  late final List<MachiningSlot> _slots = machiningSlotsForShift(widget.shift);

  final _planController = TextEditingController();
  late final Map<String, TextEditingController> _outputControllers = {
    for (final slot in _slots) slot.outputKey: TextEditingController(),
  };

  /// Backend-computed LOR% labels, keyed by lorKey.
  final Map<String, String?> _lors = {};

  /// Defect totals already saved for this entry, keyed by code|type. The sheet
  /// stores one total per type with no slot, so this is all that comes back.
  Map<String, RejectionEntry> _saved = {};

  /// Rejections typed against each time slot THIS session, keyed by outputKey.
  /// The slot is an entry aid only — it never reaches the sheet — so these are
  /// folded into the summary and cleared once saved. Anything typed here adds
  /// to what is already saved, which is why reopening the screen and typing
  /// again can't double-count.
  final Map<String, List<_RejectionRow>> _slotRows = {};

  /// Hours whose output is already on the sheet. Once logged, an hour is
  /// history: it shows as a read-only value, not an editable field. Derived
  /// from the server row on every (re)load, so submitting locks the hours
  /// that were just saved. Corrections go through the sheet itself.
  final Set<String> _lockedOutputs = {};

  /// Who logged which hour — slot ("8AM") -> {by, at}, from the row's LogMeta
  /// column. Shown under each locked hour as "Added by Ahmad at 08:07".
  Map<String, dynamic> _logMeta = {};

  static Map<String, dynamic> _parseLogMeta(dynamic raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        // A hand-edited cell that isn't JSON — no attribution, no crash.
      }
    }
    return {};
  }

  /// Per-hour rejections that were saved earlier THIS session, shown read-only
  /// under their hour. The sheet keeps only the per-type totals — the hour is
  /// not stored — so after the screen is closed this per-hour view is gone and
  /// history lives in the summary instead.
  final Map<String, List<RejectionEntry>> _loggedSlotRejections = {};

  /// Encoded snapshot of the saved totals, to tell whether they changed.
  String _initialRejections = '[]';

  /// Values as loaded from the server, to detect what changed this session.
  Map<String, String> _initial = {};

  bool _loading = true;
  String? _loadError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _planController.dispose();
    for (final controller in _outputControllers.values) {
      controller.dispose();
    }
    for (final rows in _slotRows.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    _sheetsService.dispose();
    super.dispose();
  }

  /// Resets the per-slot rows to one empty row per checkpoint. Called on load
  /// and after a successful save, when everything typed has become a saved
  /// total and would otherwise be counted a second time.
  void _resetSlotRows() {
    for (final rows in _slotRows.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    _slotRows.clear();
    for (final slot in _slots) {
      _slotRows[slot.outputKey] = [_RejectionRow()];
    }
  }

  /// What the sheet gets: the saved totals plus everything typed against the
  /// slots this session, added up per defect type. The slot itself is dropped —
  /// the sheet holds one total per type, exactly as before.
  List<RejectionEntry> get _rejectionSummary {
    final totals = <String, RejectionEntry>{};
    _saved.forEach((key, entry) {
      totals[key] = RejectionEntry(
        qty: entry.qty,
        code: entry.code,
        type: entry.type,
      );
    });

    for (final rows in _slotRows.values) {
      for (final row in rows) {
        final added = double.tryParse(row.qtyController.text.trim());
        final type = row.entry.type.trim();
        if (added == null || added == 0 || type.isEmpty) continue;
        final key = '${row.entry.code}|$type';
        final running = double.tryParse(totals[key]?.qty ?? '') ?? 0;
        totals[key] = RejectionEntry(
          qty: _trimNumber(running + added),
          code: row.entry.code,
          type: type,
        );
      }
    }
    return totals.values.toList();
  }

  String _encodeRejections() =>
      jsonEncode([for (final entry in _rejectionSummary) entry.toJson()]);

  /// 8.0 -> "8", 8.5 -> "8.5" — piece counts shouldn't grow a decimal point.
  static String _trimNumber(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final row = await _sheetsService.fetchMachiningRow(
        customer: widget.customer,
        part: widget.part,
        line: widget.line,
        shift: widget.shift,
      );
      if (!mounted) return;
      setState(() {
        _planController.text = row?.value('Plan') ?? '';
        _lockedOutputs.clear();
        for (final slot in _slots) {
          final saved = row?.value(slot.outputKey);
          _outputControllers[slot.outputKey]!.text = saved ?? '';
          if (saved != null && saved.isNotEmpty) {
            _lockedOutputs.add(slot.outputKey);
          }
          _lors[slot.lorKey] = row?.lorLabel(slot.lorKey);
        }
        _logMeta = _parseLogMeta(row?.raw['LogMeta']);
        _saved = {
          for (final entry in row?.rejections ?? <RejectionEntry>[])
            '${entry.code}|${entry.type}': entry,
        };
        _resetSlotRows();
        _initialRejections = _encodeRejections();
        _initial = _currentValues();
        _loading = false;
      });
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      setState(() {
        // Keep the form usable offline-ish: empty fields, banner on top.
        _resetSlotRows();
        _initial = _currentValues();
        _loadError = error.message;
        _loading = false;
      });
    }
  }

  Map<String, String> _currentValues() => {
    'Plan': _planController.text.trim(),
    for (final slot in _slots)
      slot.outputKey: _outputControllers[slot.outputKey]!.text.trim(),
  };

  /// Non-empty fields whose value differs from what the server had.
  Map<String, String> _changedFields() {
    final changed = <String, String>{};
    _currentValues().forEach((key, value) {
      if (value.isNotEmpty && value != (_initial[key] ?? '')) {
        changed[key] = value;
      }
    });
    return changed;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final changed = _changedFields();
    // The list is posted whole (it replaces the entry's rows server-side), so
    // send it only when it actually differs — otherwise a plain output edit
    // would rewrite defect rows for no reason.
    final rejections = _encodeRejections();
    if (rejections != _initialRejections) {
      changed['Rejections'] = rejections;
    }
    if (changed.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Nothing new to save yet.'),
          ),
        );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _sheetsService.submitMachiningUpdate({
        'Customer': widget.customer,
        'PartNo': widget.part,
        'Line': widget.line,
        'Shift': widget.shift,
        ...changed,
      });
      if (!mounted) return;
      showSaveSuccessSnack(context);
      // Freeze this session's hourly rejections into read-only history under
      // their hour, before the reload wipes the editable rows.
      _captureLoggedRejections();
      // Re-fetch so freshly computed LOR% values appear and the hours that
      // were just saved lock.
      await _load();
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      showSubmissionError(context, message: error.message, onRetry: _submit);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Folds this session's completed hourly entries into the read-only
  /// per-hour history, merging repeats of the same defect within an hour.
  void _captureLoggedRejections() {
    for (final slot in _slots) {
      for (final row in _slotRows[slot.outputKey] ?? const <_RejectionRow>[]) {
        final qty = double.tryParse(row.qtyController.text.trim());
        final type = row.entry.type.trim();
        if (qty == null || qty == 0 || type.isEmpty) continue;
        final list = _loggedSlotRejections.putIfAbsent(
          slot.outputKey,
          () => [],
        );
        RejectionEntry? existing;
        for (final entry in list) {
          if (entry.code == row.entry.code && entry.type == type) {
            existing = entry;
            break;
          }
        }
        if (existing != null) {
          existing.qty = _trimNumber(
            (double.tryParse(existing.qty) ?? 0) + qty,
          );
        } else {
          list.add(
            RejectionEntry(
              qty: _trimNumber(qty),
              code: row.entry.code,
              type: type,
            ),
          );
        }
      }
    }
  }

  /// Opens the defect-type picker for one rejection row. The master list
  /// (~230 types) is fetched once per session by the service.
  Future<void> _pickType(_RejectionRow row) async {
    List<RejectionType> types;
    try {
      types = await _sheetsService.fetchRejectionTypes();
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.danger,
          ),
        );
      return;
    }
    if (!mounted) return;
    if (types.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No rejection types found — import the rejection CSV first.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      return;
    }

    final picked = await promptRejectionType(
      context,
      types: types,
      initialCode: row.entry.code,
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.entry
        ..code = picked.code
        ..type = picked.type;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle:
            'Machining — ${widget.customer} · Part ${widget.part} · '
            '${widget.line} · ${widget.shift} shift',
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.steelBlue),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimens.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ContextHeader(
                        customer: widget.customer,
                        part: widget.part,
                        line: widget.line,
                        shift: widget.shift,
                        mo: widget.mo,
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 14),
                        _LoadErrorBanner(message: _loadError!, onRetry: _load),
                      ],
                      const SizedBox(height: AppDimens.fieldSpacing),
                      AppNumberField(
                        label: 'Plan',
                        controller: _planController,
                        required: false,
                      ),
                      for (final slot in _slots) ...[
                        const SizedBox(height: AppDimens.fieldSpacing),
                        _SlotBlock(
                          slot: slot,
                          outputController: _outputControllers[slot.outputKey]!,
                          lorLabel: _lors[slot.lorKey],
                          locked: _lockedOutputs.contains(slot.outputKey),
                          stamp:
                              _logMeta[slot.outputKey.replaceFirst(
                                    'Output_',
                                    '',
                                  )]
                                  as Map?,
                          logged:
                              _loggedSlotRejections[slot.outputKey] ?? const [],
                          rows: _slotRows[slot.outputKey]!,
                          onPickType: _pickType,
                          onQtyChanged: () => setState(() {}),
                          onAddRow: () => setState(
                            () =>
                                _slotRows[slot.outputKey]!.add(_RejectionRow()),
                          ),
                          onRemoveRow: (row) => setState(() {
                            _slotRows[slot.outputKey]!.remove(row);
                            row.dispose();
                          }),
                        ),
                      ],
                      const SizedBox(height: 26),
                      _RejectionSummary(entries: _rejectionSummary),
                      const SizedBox(height: 28),
                      SubmitButton(
                        onPressed: _submit,
                        busy: _submitting,
                        label: 'SAVE LOG',
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Customer / Part / Line / Shift / MO context chips so the supervisor always
/// knows where this entry is going. MO is read-only here — edit it from the
/// part's Edit action on the Parts screen.
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.customer,
    required this.part,
    required this.line,
    required this.shift,
    this.mo,
  });

  final String customer;
  final String part;
  final String line;
  final String shift;
  final String? mo;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.amber),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip(Icons.precision_manufacturing_rounded, customer),
        chip(Icons.tag_rounded, 'Part $part'),
        chip(Icons.linear_scale_rounded, line),
        chip(
          shift == 'Night' ? Icons.nightlight_round : Icons.wb_sunny_rounded,
          '$shift shift',
        ),
        if (mo != null) chip(Icons.description_outlined, 'MO $mo'),
      ],
    );
  }
}

/// Non-blocking banner when today's saved row could not be fetched: the
/// form still works, but pre-fill/LOR data is missing.
class _LoadErrorBanner extends StatelessWidget {
  const _LoadErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Saved data could not be loaded — $message',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A4A00),
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'RETRY',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable rejection line: which defect, and how many. Paired with a
/// controller so the quantity survives rebuilds while rows are added/removed.
class _RejectionRow {
  _RejectionRow();

  final RejectionEntry entry = RejectionEntry();
  final TextEditingController qtyController = TextEditingController();

  void dispose() => qtyController.dispose();
}

/// One time slot: output field + LOR% badge, with that hour's rejections
/// directly beneath — logged as the hour is logged, rather than collected
/// separately at the end.
///
/// An hour whose output is already on the sheet is history: its value shows
/// in a read-only box with a lock, and rejections saved for it this session
/// show as read-only lines. More defects can still be added for that hour.
class _SlotBlock extends StatelessWidget {
  const _SlotBlock({
    required this.slot,
    required this.outputController,
    required this.lorLabel,
    required this.locked,
    required this.stamp,
    required this.logged,
    required this.rows,
    required this.onPickType,
    required this.onQtyChanged,
    required this.onAddRow,
    required this.onRemoveRow,
  });

  final MachiningSlot slot;
  final TextEditingController outputController;
  final String? lorLabel;

  /// True when this hour's output is already saved to the sheet.
  final bool locked;

  /// {by, at} for a locked hour — who logged it and when, from LogMeta.
  final Map? stamp;

  /// Rejections saved for this hour earlier this session (read-only).
  final List<RejectionEntry> logged;
  final List<_RejectionRow> rows;
  final void Function(_RejectionRow row) onPickType;
  final VoidCallback onQtyChanged;
  final VoidCallback onAddRow;
  final void Function(_RejectionRow row) onRemoveRow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _outputRow(),
        for (final entry in logged) _loggedRow(entry),
        for (final row in rows) _rejectionRow(row),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAddRow,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Another defect this hour'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.steelBlue,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }

  /// A rejection already saved for this hour: same shape as the editable row,
  /// but frozen — recorded scrap is corrected in the sheet, not on the floor.
  Widget _loggedRow(RejectionEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 12),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '× ${entry.qty}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.lock_outline,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Keeps the frozen line aligned with the editable rows' ✕ column.
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _rejectionRow(_RejectionRow row) {
    final canRemove = rows.length > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 12),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _TypeField(entry: row.entry, onTap: () => onPickType(row)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextFormField(
              controller: row.qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: (_) => onQtyChanged(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: 'Qty',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: canRemove
                ? IconButton(
                    onPressed: () => onRemoveRow(row),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _outputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: locked
              ? _lockedOutput()
              : AppNumberField(
                  label: 'Output — ${slot.label}',
                  controller: outputController,
                  required: false,
                ),
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            // Spacer matching the field label height keeps the badge
            // aligned with the input box.
            const SizedBox(height: 27),
            Container(
              width: 88,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.steelBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.steelBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'LOR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    lorLabel ?? '—',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.steelBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// An hour that's already on the sheet: the value is shown, not editable.
  /// Mistakes are corrected in the sheet itself, not by overtyping history.
  Widget _lockedOutput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: 'Output — ${slot.label}', required: false),
        const SizedBox(height: 6),
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Text(
                outputController.text,
                style: TextStyle(
                  fontSize: AppDimens.fieldFontSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.lock_outline,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
        if (stamp != null && stamp!['by'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              'Added by ${stamp!['by']}'
              '${stamp!['at'] != null ? ' at ${stamp!['at']}' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// The auto-calculated total per defect type for the day — the sum of the
/// hourly entries above plus whatever was already saved. This is exactly what
/// is written to the sheet; the hourly split is an entry aid and is not stored.
///
/// Deliberately display-only: recorded scrap must not be erasable from the
/// floor, so there is no remove here. A wrong figure is corrected in the
/// sheet itself.
class _RejectionSummary extends StatelessWidget {
  const _RejectionSummary({required this.entries});

  final List<RejectionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(
      0,
      (sum, e) => sum + (double.tryParse(e.qty) ?? 0),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_outlined, size: 20, color: AppColors.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rejection summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                'saved to sheet',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (entries.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No rejections logged this shift.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 6),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      entry.qty,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    total % 1 == 0
                        ? total.toInt().toString()
                        : total.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Looks and behaves like a dropdown, but opens a searchable dialog — the
/// master list runs to ~230 defect types, far too many for a plain menu.
class _TypeField extends StatelessWidget {
  const _TypeField({required this.entry, required this.onTap});

  final RejectionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chosen = entry.type.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Rejection type',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                chosen ? entry.label : 'Select type',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                  color: chosen
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
