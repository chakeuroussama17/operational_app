import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../models/part_code.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
import '../widgets/fill_tank_card.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';
import 'machining_entry_screen.dart';

/// Part selector for one customer + operation. Since the Line step was
/// removed this is the level that opens the entry form, so the cards are
/// fill-tanks showing how much of the shift is already logged.
class MachiningPartsScreen extends StatefulWidget {
  const MachiningPartsScreen({
    super.key,
    required this.customer,
    required this.operation,
    required this.shift,
  });

  final String customer;
  final MachiningOperation operation;
  final String shift;

  @override
  State<MachiningPartsScreen> createState() => _MachiningPartsScreenState();
}

class _MachiningPartsScreenState extends State<MachiningPartsScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  List<MachiningPartStatus> _parts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sheetsService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parts = await _sheetsService.fetchMachiningParts(
        widget.customer,
        shift: widget.shift,
        operation: widget.operation.value,
      );
      if (!mounted) return;
      setState(() {
        _parts = parts;
        _loading = false;
      });
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _openPart(MachiningPartStatus part) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => MachiningEntryScreen(
              customer: widget.customer,
              part: part.part,
              operation: widget.operation,
              shift: widget.shift,
              mo: part.mo,
            ),
          ),
        )
        .then((_) => _load());
  }

  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      await _load();
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
    }
  }

  Future<void> _addPart() async {
    final codes = await _availableCodes();
    if (codes == null || !mounted) return;
    final input = await promptPartCode(
      context,
      title: 'Add Part',
      moduleLabel: 'Machining',
      codes: codes,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.addMachiningPart(
        customer: widget.customer,
        part: input.name,
        mo: input.mo.isEmpty ? null : input.mo,
      ),
    );
  }

  Future<void> _editPart(MachiningPartStatus part) async {
    final codes = await _availableCodes();
    if (codes == null || !mounted) return;
    final input = await promptPartCode(
      context,
      title: 'Edit Part',
      moduleLabel: 'Machining',
      codes: codes,
      initialCode: part.part,
      initialMo: part.mo,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.editMachiningPart(
        customer: widget.customer,
        part: part.part,
        newPart: input.name,
        mo: input.mo,
      ),
    );
  }

  /// Part codes for Machining (from the Parts master), or null after telling
  /// the user why the picker can't open.
  Future<List<PartCode>?> _availableCodes() async {
    try {
      final codes = await _sheetsService.fetchPartCodes('machining');
      if (!mounted) return null;
      if (codes.isEmpty) {
        _snack('No Machining part codes found — import the Parts sheet first.');
        return null;
      }
      return codes;
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return null;
      _snack(error.message);
      return null;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
  }

  Future<void> _deletePart(MachiningPartStatus part) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete Part ${part.part}?',
      message:
          'Historical logs already saved are not affected. '
          'This cannot be undone.',
    );
    if (confirmed != true) return;
    await _mutate(
      () => _sheetsService.configDelete(
        module: 'machining',
        kind: 'part',
        group: widget.customer,
        value: part.part,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle:
            'Machining — ${widget.operation.label} · ${widget.customer} · '
            '${widget.shift} shift',
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.screenPadding,
                AppDimens.screenPadding,
                AppDimens.screenPadding,
                8,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select part',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to log · ⋮ to rename or delete',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.steelBlue),
      );
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      color: AppColors.steelBlue,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 640 ? 3 : 2;
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimens.screenPadding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppDimens.fieldSpacing,
              crossAxisSpacing: AppDimens.fieldSpacing,
              childAspectRatio: 1.0,
            ),
            itemCount: _parts.length + 1,
            itemBuilder: (context, index) {
              if (index == _parts.length) {
                return AddTile(label: 'Add Part', onTap: _addPart);
              }
              final part = _parts[index];
              return Stack(
                children: [
                  Positioned.fill(
                    child: FillTankCard(
                      title: part.part,
                      subtitle: _partSubtitle(part),
                      fillPercent: part.fillPercent,
                      onTap: () => _openPart(part),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: CardMenuButton(
                      onEdit: () => _editPart(part),
                      onDelete: () => _deletePart(part),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// "MO X · HH:mm" / "MO X" / "Last updated: HH:mm" / "No entries yet today".
String _partSubtitle(MachiningPartStatus part) {
  final name = part.name;
  final mo = part.mo;
  final updated = part.lastUpdated;
  if (name != null) return mo != null ? 'MO $mo · $name' : name;
  if (mo != null && updated != null) return 'MO $mo · $updated';
  if (mo != null) return 'MO $mo';
  if (updated != null) return 'Last updated: $updated';
  return 'No entries yet today';
}
