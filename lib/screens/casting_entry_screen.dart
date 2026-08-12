import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/casting_models.dart';
import '../services/sheets_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/submission_feedback.dart';
import '../widgets/submit_button.dart';

/// Data entry for one DCM + Part + Shift. Pre-fills this shift's saved
/// values, lets the supervisor fill any subset of time slots, and submits
/// only the fields that changed — the backend upserts and recalculates LOR%.
class CastingEntryScreen extends StatefulWidget {
  const CastingEntryScreen({
    super.key,
    required this.dcm,
    required this.part,
    required this.shift,
    this.mo,
  });

  final String dcm;
  final String part;
  final String shift;

  /// The part's MO (manufacturing order) number, as of when the Parts
  /// screen loaded it — shown as read-only context, not editable here (see
  /// the part's Edit action on the Parts screen for that).
  final String? mo;

  @override
  State<CastingEntryScreen> createState() => _CastingEntryScreenState();
}

class _CastingEntryScreenState extends State<CastingEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sheetsService = SheetsService();

  late final List<CastingSlot> _slots = castingSlotsForShift(widget.shift);

  final _planController = TextEditingController();
  late final Map<String, TextEditingController> _slotControllers = {
    for (final slot in _slots) slot.outputKey: TextEditingController(),
  };

  /// Backend-computed LOR% labels, keyed by lorKey.
  final Map<String, String?> _lors = {};

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
    for (final controller in _slotControllers.values) {
      controller.dispose();
    }
    _sheetsService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final row = await _sheetsService.fetchCastingRow(
        dcm: widget.dcm,
        part: widget.part,
        shift: widget.shift,
      );
      if (!mounted) return;
      setState(() {
        _planController.text = row?.value('Plan') ?? '';
        for (final slot in _slots) {
          _slotControllers[slot.outputKey]!.text =
              row?.value(slot.outputKey) ?? '';
          _lors[slot.lorKey] = row?.lorLabel(slot.lorKey);
        }
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
      slot.outputKey: _slotControllers[slot.outputKey]!.text.trim(),
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
      await _sheetsService.submitCastingUpdate({
        'DCM': widget.dcm,
        'PartNo': widget.part,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle:
            'Casting — DCM ${widget.dcm} · Part ${widget.part} · '
            '${widget.shift} shift',
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
                        dcm: widget.dcm,
                        part: widget.part,
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
                        _SlotRow(
                          slot: slot,
                          controller: _slotControllers[slot.outputKey]!,
                          lorLabel: _lors[slot.lorKey],
                        ),
                      ],
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

/// DCM / Part / Shift / MO context chips so the supervisor always knows
/// where this entry is going. MO is read-only here — edit it from the
/// part's Edit action on the Parts screen.
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.dcm,
    required this.part,
    required this.shift,
    this.mo,
  });

  final String dcm;
  final String part;
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
        chip(Icons.local_fire_department_rounded, 'DCM $dcm'),
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

/// One time slot: editable output field + read-only LOR% badge beside it.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.controller,
    required this.lorLabel,
  });

  final CastingSlot slot;
  final TextEditingController controller;
  final String? lorLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppNumberField(
            label: 'Actual — ${slot.label}',
            controller: controller,
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
