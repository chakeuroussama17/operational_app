import 'dart:convert';

import 'package:flutter/material.dart';

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
  });

  final String customer;
  final String part;
  final String line;
  final String shift;

  /// The part's MO (manufacturing order) number — shown as read-only context.
  /// Edit it from the part's Edit action on the Parts screen.
  final String? mo;

  @override
  State<MachiningEntryScreen> createState() => _MachiningEntryScreenState();
}

class _MachiningEntryScreenState extends State<MachiningEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sheetsService = SheetsService();

  late final List<MachiningSlot> _slots = machiningSlotsForShift(widget.shift);

  final _planController = TextEditingController();
  late final Map<String, TextEditingController> _outputControllers = {
    for (final slot in _slots) slot.outputKey: TextEditingController(),
  };

  /// Backend-computed LOR% labels, keyed by lorKey.
  final Map<String, String?> _lors = {};

  /// The defect list for this entry — any number of "N of this type" rows.
  /// Posted whole on submit, replacing whatever the sheet held.
  List<RejectionEntry> _rejections = [];
  List<TextEditingController> _qtyControllers = [];

  /// Encoded snapshot of the loaded list, to tell whether it was edited.
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
    for (final controller in _qtyControllers) {
      controller.dispose();
    }
    _sheetsService.dispose();
    super.dispose();
  }

  void _setRejections(List<RejectionEntry> entries) {
    for (final controller in _qtyControllers) {
      controller.dispose();
    }
    _rejections = entries;
    _qtyControllers = [
      for (final entry in entries) TextEditingController(text: entry.qty),
    ];
  }

  /// Only complete rows go to the server — a row the user opened but never
  /// filled in is not a defect. Quantities live in the controllers, so they're
  /// pulled back onto the entries here rather than mirrored on every keystroke.
  String _encodeRejections() {
    final out = <Map<String, String>>[];
    for (var i = 0; i < _rejections.length; i++) {
      final entry = _rejections[i]..qty = _qtyControllers[i].text.trim();
      if (entry.isComplete) out.add(entry.toJson());
    }
    return jsonEncode(out);
  }

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
        for (final slot in _slots) {
          _outputControllers[slot.outputKey]!.text =
              row?.value(slot.outputKey) ?? '';
          _lors[slot.lorKey] = row?.lorLabel(slot.lorKey);
        }
        _setRejections(row?.rejections ?? []);
        _initialRejections = _encodeRejections();
        _initial = _currentValues();
        _loading = false;
      });
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      setState(() {
        // Keep the form usable offline-ish: empty fields, banner on top.
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
      // Re-fetch so freshly computed LOR% values appear.
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
  Future<void> _pickType(int index) async {
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
      initialCode: _rejections[index].code,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _rejections[index]
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
                        ),
                      ],
                      const SizedBox(height: 26),
                      _RejectionSection(
                        entries: _rejections,
                        qtyControllers: _qtyControllers,
                        onAdd: () => setState(() {
                          _rejections.add(RejectionEntry());
                          _qtyControllers.add(TextEditingController());
                        }),
                        onRemove: (index) => setState(() {
                          _rejections.removeAt(index);
                          _qtyControllers.removeAt(index).dispose();
                        }),
                        onPickType: (index) => _pickType(index),
                      ),
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

/// One time slot: editable output field + read-only LOR% badge.
class _SlotBlock extends StatelessWidget {
  const _SlotBlock({
    required this.slot,
    required this.outputController,
    required this.lorLabel,
  });

  final MachiningSlot slot;
  final TextEditingController outputController;
  final String? lorLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppNumberField(
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
}

/// The defect list for the whole entry: rows of "how many" + "of what type",
/// with a + to add another. Sits just above SAVE, after the time slots.
class _RejectionSection extends StatelessWidget {
  const _RejectionSection({
    required this.entries,
    required this.qtyControllers,
    required this.onAdd,
    required this.onRemove,
    required this.onPickType,
  });

  final List<RejectionEntry> entries;
  final List<TextEditingController> qtyControllers;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(int index) onPickType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.report_gmailerrorred, size: 20, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(
              'Rejections',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(optional)',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'How many of each defect this shift — add a row per type.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        for (var i = 0; i < entries.length; i++) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 96,
                child: AppNumberField(
                  label: 'Qty',
                  controller: qtyControllers[i],
                  required: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeField(
                  entry: entries[i],
                  onTap: () => onPickType(i),
                ),
              ),
              IconButton(
                onPressed: () => onRemove(i),
                icon: const Icon(Icons.close),
                color: AppColors.textSecondary,
                tooltip: 'Remove this rejection',
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(entries.isEmpty ? 'ADD REJECTION' : 'ADD ANOTHER'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              side: BorderSide(color: AppColors.navy.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        ),
      ],
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
