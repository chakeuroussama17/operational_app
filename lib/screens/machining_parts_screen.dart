import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../models/part_code.dart';
import '../services/sheets_service.dart';
import '../widgets/module_shell.dart';
import 'auth_gate.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
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
    this.service,
  });

  final String customer;
  final MachiningOperation operation;
  final String shift;

  /// Test seam: the screen normally builds its own [SheetsService] against
  /// the real backend; widget tests inject one backed by a mock client.
  final SheetsService? service;

  @override
  State<MachiningPartsScreen> createState() => _MachiningPartsScreenState();
}

class _MachiningPartsScreenState extends State<MachiningPartsScreen> {
  late final _sheetsService = widget.service ?? SheetsService();

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
              lineName: part.lineName,
              lineNo: part.lineNo,
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
      moduleLabel: widget.operation.label,
      codes: codes,
      pickLine: true,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.addMachiningPart(
        customer: widget.customer,
        part: input.name,
        operation: widget.operation.value,
        lineName: input.lineName,
        lineNo: input.lineNo,
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
      moduleLabel: widget.operation.label,
      codes: codes,
      initialCode: part.part,
      initialMo: part.mo,
      pickLine: true,
      initialLine: part.line,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.editMachiningPart(
        customer: widget.customer,
        part: part.part,
        newPart: input.name,
        operation: widget.operation.value,
        // Which entry is being edited, and where it ends up — the pair is
        // how a part gets moved from one line to another.
        lineName: part.lineName,
        lineNo: part.lineNo,
        newLineName: input.lineName,
        newLineNo: input.lineNo,
        mo: input.mo,
      ),
    );
  }

  /// This operation's half of the Parts master, or null after telling the user
  /// why the picker can't open. The whole machining list is fetched (and
  /// cached) once, then split by suffix — so switching operation costs nothing.
  Future<List<PartCode>?> _availableCodes() async {
    try {
      final all = await _sheetsService.fetchPartCodes('machining');
      if (!mounted) return null;
      if (all.isEmpty) {
        _snack('No Machining part codes found — import the Parts sheet first.');
        return null;
      }
      final codes = partCodesForOperation(all, widget.operation);
      if (codes.isEmpty) {
        _snack(
          'No ${widget.operation.label.toLowerCase()} parts in the Parts '
          'sheet — those are the ones ending in '
          '${widget.operation.value == 'machining' ? 'MACH' : 'ASSY'}.',
        );
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
      title: part.line.isEmpty
          ? 'Delete Part ${part.part}?'
          : 'Delete ${part.part} on ${part.line}?',
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
        // Scoped, or deleting from machining takes it out of assembly too.
        operation: widget.operation.value,
        // And scoped again by line, or deleting the part from one line
        // takes it off every other line running it.
        lineName: part.lineName,
        lineNo: part.lineNo,
      ),
    );
  }


  /// Whether the signed-in person may change what the plant makes. Operators
  /// log production; adding or removing a part or a customer decides what
  /// everyone else logs against for months, so it is a super admin's act.
  ///
  /// The backend refuses either way — this only stops offering a control that
  /// would come back as an error. Absent a session (widget tests pump these
  /// screens bare) there is nothing to gate on, so the controls stay.
  bool get _canManage =>
      AuthScope.maybeOf(context)?.user.canManageConfig ?? true;

  @override
Widget build(BuildContext context) {
    return ModuleScaffold(
      subtitle:
          'Machining — ${widget.operation.label} · ${widget.customer} · '
          '${widget.shift} shift',
      headline: 'Select part',
      hint: 'Tap to log · ⋮ to rename or delete',
      child: _body(),
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
      // A list, not a grid: the card is a horizontal row (icon, text,
      // progress) and squeezing that into a 2-up grid is what made these
      // screens look unrelated to the home page they open from.
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDimens.screenPadding,
          4,
          AppDimens.screenPadding,
          28,
        ),
        itemCount: _parts.length + (_canManage ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _parts.length) {
            return SizedBox(
              height: 88,
              child: AddCard(label: 'Add part', onTap: _addPart),
            );
          }
          final part = _parts[index];
          return SelectorCard(
            title: part.part,
            subtitle: _partSubtitle(part),
            icon: Icons.tag_rounded,
            onTap: () => _openPart(part),
            fillPercent: part.fillPercent,
            trailing: !_canManage
                ? null
                : CardMenuButton(
              onEdit: () => _editPart(part),
              onDelete: () => _deletePart(part),
            ),
          );
        },
      ),
    );
  }
}

/// "Fanuc 21 · MO X · HH:mm" and so on down to "No entries yet today".
///
/// The line leads, because it is the only thing distinguishing two cards
/// that share a part code — which is the whole reason it is asked for.
String _partSubtitle(MachiningPartStatus part) {
  final parts = <String>[
    if (part.line.isNotEmpty) part.line,
    if (part.mo != null) 'MO ${part.mo}',
    if (part.name != null) part.name!,
  ];
  if (parts.isEmpty) {
    final updated = part.lastUpdated;
    return updated != null ? 'Last updated: $updated' : 'No entries yet today';
  }
  // The timestamp only earns its place when nothing else has taken the line.
  if (parts.length == 1 && part.lastUpdated != null) {
    parts.add(part.lastUpdated!);
  }
  return parts.join(' · ');
}
