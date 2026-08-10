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

/// Data entry for one Operation + Customer + Part + Shift. Pre-fills this
/// shift's
/// saved values, lets the supervisor fill any subset of time slots, and
/// submits only the fields that changed — the backend upserts and
/// recalculates LOR%.
class MachiningEntryScreen extends StatefulWidget {
  const MachiningEntryScreen({
    super.key,
    required this.customer,
    required this.part,
    required this.operation,
    required this.shift,
    this.mo,
    this.service,
  });

  final String customer;
  final String part;
  final MachiningOperation operation;
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

  /// Backend-computed LOR% labels, keyed by lorKey. Only a fallback: with a
  /// Plan on the row the badge shows a live cumulative figure instead, so a
  /// pending correction is visible before it is saved.
  final Map<String, String?> _lors = {};

  /// Defects already on the sheet for this entry, grouped by the hour they
  /// were logged against. The type is settled — only the quantity can still
  /// be corrected, and correcting it moves pieces between scrap and output.
  final Map<String, List<_SavedRejection>> _savedRows = {};

  /// Defects saved before the sheet tracked the hour. Shown in the summary for
  /// completeness and never re-posted, so the backend leaves them alone.
  List<RejectionEntry> _legacyRejections = [];

  /// New defects being typed against each time slot, keyed by outputKey. These
  /// are the good-parts-already-excluded kind: the output typed beside them
  /// is the good count, so logging one does not change the output.
  final Map<String, List<_RejectionRow>> _slotRows = {};

  /// Hours whose output is already on the sheet. Once logged, an hour is
  /// history: it shows as a read-only value, not an editable field. Derived
  /// from the server row on every (re)load, so submitting locks the hours
  /// that were just saved. The only way it moves after that is a rejection
  /// correction handing pieces back.
  final Set<String> _lockedOutputs = {};

  /// True once the shift's Plan is on the sheet: the whole shift's LOR hangs
  /// off it, so it is set once and then read-only.
  bool _planLocked = false;

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
    _disposeRejectionRows();
    _sheetsService.dispose();
    super.dispose();
  }

  void _disposeRejectionRows() {
    for (final rows in _slotRows.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    for (final rows in _savedRows.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
  }

  /// Resets the per-slot rows to one empty row per checkpoint. Called on load
  /// and after a successful save, when everything typed has come back from the
  /// sheet as saved history and would otherwise be counted a second time.
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

  /// This shift's defect totals per type: what the sheet holds (at the
  /// quantities currently shown, corrections included) plus anything new being
  /// typed. Display only — the sheet is written per hour.
  List<RejectionEntry> get _rejectionSummary {
    final totals = <String, RejectionEntry>{};

    void add(String code, String type, double qty) {
      if (type.isEmpty || qty == 0) return;
      final key = '$code|$type';
      final running = double.tryParse(totals[key]?.qty ?? '') ?? 0;
      totals[key] = RejectionEntry(
        qty: _trimNumber(running + qty),
        code: code,
        type: type,
      );
    }

    for (final rows in _savedRows.values) {
      for (final row in rows) {
        add(row.code, row.type, double.tryParse(row.qty) ?? 0);
      }
    }
    for (final entry in _legacyRejections) {
      add(entry.code, entry.type, double.tryParse(entry.qty) ?? 0);
    }
    for (final rows in _slotRows.values) {
      for (final row in rows) {
        add(
          row.entry.code,
          row.entry.type.trim(),
          double.tryParse(row.qtyController.text.trim()) ?? 0,
        );
      }
    }
    return totals.values.toList();
  }

  /// What actually gets posted: corrected saved lines and completed new ones,
  /// each tagged with its hour. Lines the sheet holds that nobody touched are
  /// left out — the backend keeps rows a payload doesn't mention, so a save
  /// can never quietly wipe recorded scrap.
  List<RejectionEntry> _rejectionPayload() {
    final payload = <RejectionEntry>[];
    for (final slot in _slots) {
      for (final row
          in _savedRows[slot.outputKey] ?? const <_SavedRejection>[]) {
        if (row.isCorrected) {
          payload.add(
            RejectionEntry(
              qty: row.qty,
              code: row.code,
              type: row.type,
              slot: slot.slotKey,
            ),
          );
        }
      }
      for (final row in _slotRows[slot.outputKey] ?? const <_RejectionRow>[]) {
        // The quantity lives in the controller, so ask it — not entry.qty,
        // which is only ever filled in on the way out.
        final qty = row.qtyController.text.trim();
        if (qty.isEmpty || row.entry.type.trim().isEmpty) continue;
        payload.add(
          RejectionEntry(
            qty: qty,
            code: row.entry.code,
            type: row.entry.type.trim(),
            slot: slot.slotKey,
          ),
        );
      }
    }
    return payload;
  }

  /// The output an hour will hold once pending corrections are saved: pieces
  /// reclassified out of scrap come back to it.
  String _projectedOutput(MachiningSlot slot) {
    final saved = double.tryParse(
      _outputControllers[slot.outputKey]!.text.trim(),
    );
    if (saved == null) return _outputControllers[slot.outputKey]!.text.trim();
    var total = saved;
    for (final row in _savedRows[slot.outputKey] ?? const <_SavedRejection>[]) {
      total += row.returnedPieces;
    }
    return _trimNumber(total);
  }

  /// Running output over Plan, up to and including [slot] — LOR answers "how
  /// much of the plan is done so far", so it accumulates across the shift.
  /// Computed live from the projected outputs so a correction shows up before
  /// it is saved; falls back to the server's cell when there is no Plan.
  String? _lorLabel(MachiningSlot slot) {
    final plan = double.tryParse(_planController.text.trim());
    if (plan == null || plan <= 0) return _lors[slot.lorKey];
    var running = 0.0;
    var reached = false;
    for (final s in _slots) {
      final value = double.tryParse(_projectedOutput(s));
      if (value != null) running += value;
      if (s.outputKey == slot.outputKey) {
        reached = value != null;
        break;
      }
    }
    if (!reached) return null;
    return formatLor(running / plan * 100);
  }

  /// Every hour's projected output added up — plan-versus-actual at a glance.
  double get _outputTotal {
    var total = 0.0;
    for (final slot in _slots) {
      total += double.tryParse(_projectedOutput(slot)) ?? 0;
    }
    return total;
  }

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
        operation: widget.operation.value,
        shift: widget.shift,
      );
      if (!mounted) return;
      setState(() {
        final plan = row?.value('Plan') ?? '';
        _planController.text = plan;
        _planLocked = plan.isNotEmpty;
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
        _loadSavedRejections(row?.rejections ?? const []);
        _resetSlotRows();
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

  /// Files the sheet's defect rows under the hour each was logged against.
  /// Rows written before the sheet tracked the hour have nowhere to sit, so
  /// they stay in the summary and are never re-posted.
  void _loadSavedRejections(List<RejectionEntry> entries) {
    for (final rows in _savedRows.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    _savedRows.clear();
    _legacyRejections = [];
    final known = {for (final slot in _slots) slot.slotKey: slot.outputKey};
    for (final entry in entries) {
      final outputKey = known[entry.slot];
      if (outputKey == null) {
        _legacyRejections.add(entry);
        continue;
      }
      _savedRows
          .putIfAbsent(outputKey, () => [])
          .add(
            _SavedRejection(
              code: entry.code,
              type: entry.type,
              savedQty: entry.qty,
            ),
          );
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
    final rejections = _rejectionPayload();
    if (rejections.isNotEmpty) {
      changed['Rejections'] = jsonEncode([
        for (final entry in rejections) entry.toJson(),
      ]);
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
        'Operation': widget.operation.value,
        'Shift': widget.shift,
        ...changed,
      });
      if (!mounted) return;
      showSaveSuccessSnack(context);
      // Re-fetch: the hours just saved lock, corrected outputs come back
      // adjusted, and every defect returns filed under its own hour.
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
            'Machining — ${widget.operation.label} · ${widget.customer} · '
            'Part ${widget.part} · ${widget.shift} shift',
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
                        operation: widget.operation,
                        shift: widget.shift,
                        mo: widget.mo,
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 14),
                        _LoadErrorBanner(message: _loadError!, onRetry: _load),
                      ],
                      const SizedBox(height: AppDimens.fieldSpacing),
                      if (_planLocked)
                        _LockedField(label: 'Plan', value: _planController.text)
                      else
                        AppNumberField(
                          label: 'Plan',
                          controller: _planController,
                          required: false,
                          onChanged: (_) => setState(() {}),
                        ),
                      for (final slot in _slots) ...[
                        const SizedBox(height: AppDimens.fieldSpacing),
                        _SlotBlock(
                          slot: slot,
                          outputController: _outputControllers[slot.outputKey]!,
                          lorLabel: _lorLabel(slot),
                          locked: _lockedOutputs.contains(slot.outputKey),
                          projectedOutput: _projectedOutput(slot),
                          stamp: _logMeta[slot.slotKey] as Map?,
                          saved:
                              _savedRows[slot.outputKey] ??
                              const <_SavedRejection>[],
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
                      _ShiftTotals(
                        outputTotal: _outputTotal,
                        plan: double.tryParse(_planController.text.trim()),
                      ),
                      const SizedBox(height: 14),
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

/// Operation / Customer / Part / Shift / MO context chips so the supervisor
/// always knows where this entry is going. MO is read-only here — edit it from
/// the part's Edit action on the Parts screen.
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.customer,
    required this.part,
    required this.operation,
    required this.shift,
    this.mo,
  });

  final String customer;
  final String part;
  final MachiningOperation operation;
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
        chip(Icons.settings_rounded, operation.label),
        chip(Icons.precision_manufacturing_rounded, customer),
        chip(Icons.tag_rounded, 'Part $part'),
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

/// A defect already on the sheet. The type is settled — the picker is gone —
/// but the quantity can still be corrected, and correcting it reclassifies
/// pieces: output counts good parts, so 2 fewer rejects means 2 more good.
class _SavedRejection {
  _SavedRejection({
    required this.code,
    required this.type,
    required this.savedQty,
  }) : qtyController = TextEditingController(text: savedQty);

  final String code;
  final String type;

  /// The quantity the sheet currently holds.
  final String savedQty;
  final TextEditingController qtyController;

  String get qty => qtyController.text.trim();

  String get label => code.isEmpty ? type : '$code · $type';

  bool get isCorrected => qty.isNotEmpty && qty != savedQty;

  /// Pieces this correction hands back to the hour's output (negative when
  /// the count goes up and the output owes pieces back).
  double get returnedPieces {
    if (!isCorrected) return 0;
    return (double.tryParse(savedQty) ?? 0) - (double.tryParse(qty) ?? 0);
  }

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
    required this.projectedOutput,
    required this.stamp,
    required this.saved,
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

  /// What the output becomes once pending rejection corrections are saved.
  final String projectedOutput;

  /// {by, at} for a locked hour — who logged it and when, from LogMeta.
  final Map? stamp;

  /// Defects the sheet already holds for this hour: type fixed, qty editable.
  final List<_SavedRejection> saved;
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
        for (final entry in saved) _savedRow(entry),
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

  /// A defect the sheet already holds for this hour. The type is frozen; the
  /// quantity stays editable because a miscount is corrected here, and the
  /// pieces it releases go back into the hour's output.
  Widget _savedRow(_SavedRejection entry) {
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
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  Icon(
                    Icons.lock_outline,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextFormField(
              controller: entry.qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: (_) => onQtyChanged(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: entry.isCorrected ? AppColors.amberDark : null,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
              ),
            ),
          ),
          // Keeps the saved line aligned with the editable rows' ✕ column.
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
  /// It moves only when a rejection correction hands pieces back, and then the
  /// box shows where it is heading before the save happens.
  Widget _lockedOutput() {
    final saved = outputController.text;
    final corrected = projectedOutput != saved;
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
            border: Border.all(
              color: corrected ? AppColors.amber : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              if (corrected) ...[
                Text(
                  saved,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                Icon(
                  Icons.arrow_right_alt_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
              Text(
                projectedOutput,
                style: TextStyle(
                  fontSize: AppDimens.fieldFontSize,
                  fontWeight: FontWeight.w700,
                  color: corrected
                      ? AppColors.amberDark
                      : AppColors.textPrimary,
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

/// A value the sheet owns now: shown, not editable.
class _LockedField extends StatelessWidget {
  const _LockedField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label, required: false),
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
                value,
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
      ],
    );
  }
}

/// Where the shift stands: everything produced so far against the plan, and
/// how far there is left to go.
class _ShiftTotals extends StatelessWidget {
  const _ShiftTotals({required this.outputTotal, required this.plan});

  final double outputTotal;
  final double? plan;

  static String _n(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final remaining = plan == null ? null : plan! - outputTotal;
    final ahead = remaining != null && remaining <= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.stacked_bar_chart_rounded,
                size: 20,
                color: AppColors.navy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Output so far',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                _n(outputTotal),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              if (plan != null)
                Text(
                  ' / ${_n(plan!)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          if (remaining != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ahead ? 'Plan reached' : 'Left to plan',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  ahead ? '+${_n(-remaining)}' : _n(remaining),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ahead ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
