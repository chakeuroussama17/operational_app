import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../services/sheets_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/submission_feedback.dart';
import '../widgets/submit_button.dart';

/// Data entry for one Customer + Part + Line. Pre-fills today's saved
/// values, lets the supervisor fill any subset of time slots, and submits
/// only the fields that changed — the backend upserts and recalculates LOR%.
class MachiningEntryScreen extends StatefulWidget {
  const MachiningEntryScreen({
    super.key,
    required this.customer,
    required this.part,
    required this.line,
  });

  final String customer;
  final String part;
  final String line;

  @override
  State<MachiningEntryScreen> createState() => _MachiningEntryScreenState();
}

class _MachiningEntryScreenState extends State<MachiningEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sheetsService = SheetsService();

  final _planController = TextEditingController();
  final Map<String, TextEditingController> _outputControllers = {
    for (final slot in machiningSlots) slot.outputKey: TextEditingController(),
  };
  final Map<String, TextEditingController> _rejectionControllers = {
    for (final slot in machiningSlots)
      slot.rejectionKey: TextEditingController(),
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
    for (final controller in _outputControllers.values) {
      controller.dispose();
    }
    for (final controller in _rejectionControllers.values) {
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
      final row = await _sheetsService.fetchMachiningRow(
        customer: widget.customer,
        part: widget.part,
        line: widget.line,
      );
      if (!mounted) return;
      setState(() {
        _planController.text = row?.value('Plan') ?? '';
        for (final slot in machiningSlots) {
          _outputControllers[slot.outputKey]!.text =
              row?.value(slot.outputKey) ?? '';
          _rejectionControllers[slot.rejectionKey]!.text =
              row?.value(slot.rejectionKey) ?? '';
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
    for (final slot in machiningSlots) ...{
      slot.outputKey: _outputControllers[slot.outputKey]!.text.trim(),
      slot.rejectionKey: _rejectionControllers[slot.rejectionKey]!.text.trim(),
    },
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
      await _sheetsService.submitMachiningUpdate({
        'Customer': widget.customer,
        'PartNo': widget.part,
        'Line': widget.line,
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
            'Machining — ${widget.customer} · Part ${widget.part} · ${widget.line}',
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
                      for (final slot in machiningSlots) ...[
                        const SizedBox(height: AppDimens.fieldSpacing),
                        _SlotBlock(
                          slot: slot,
                          outputController: _outputControllers[slot.outputKey]!,
                          rejectionController:
                              _rejectionControllers[slot.rejectionKey]!,
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

/// Customer / Part / Line context chips so the supervisor always knows
/// where this entry is going.
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.customer,
    required this.part,
    required this.line,
  });

  final String customer;
  final String part;
  final String line;

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

/// One time slot: editable output field + read-only LOR% badge, plus an
/// editable rejection count field beneath.
class _SlotBlock extends StatelessWidget {
  const _SlotBlock({
    required this.slot,
    required this.outputController,
    required this.rejectionController,
    required this.lorLabel,
  });

  final MachiningSlot slot;
  final TextEditingController outputController;
  final TextEditingController rejectionController;
  final String? lorLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
        ),
        const SizedBox(height: 10),
        AppNumberField(
          label: 'Rejection — ${slot.label}',
          controller: rejectionController,
          required: false,
        ),
      ],
    );
  }
}
