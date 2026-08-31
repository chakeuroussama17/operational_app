import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/casting_models.dart';
import '../models/part_code.dart';
import '../services/sheets_service.dart';
import '../widgets/module_shell.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
import '../widgets/manage_dialogs.dart';
import 'casting_entry_screen.dart';

/// Part selector for one DCM: fill-tank cards showing this shift's progress.
class CastingPartsScreen extends StatefulWidget {
  const CastingPartsScreen({super.key, required this.dcm, required this.shift});

  final String dcm;
  final String shift;

  @override
  State<CastingPartsScreen> createState() => _CastingPartsScreenState();
}

class _CastingPartsScreenState extends State<CastingPartsScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  List<PartStatus> _parts = const [];

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
      final parts = await _sheetsService.fetchCastingParts(
        widget.dcm,
        shift: widget.shift,
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

  void _openPart(PartStatus part) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => CastingEntryScreen(
              dcm: widget.dcm,
              part: part.part,
              shift: widget.shift,
              mo: part.mo,
            ),
          ),
        )
        // Fill % / timestamps change after logging — refresh on return.
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
      moduleLabel: 'Casting',
      codes: codes,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.addCastingPart(
        dcm: widget.dcm,
        part: input.name,
        mo: input.mo.isEmpty ? null : input.mo,
      ),
    );
  }

  Future<void> _editPart(PartStatus part) async {
    final codes = await _availableCodes();
    if (codes == null || !mounted) return;
    final input = await promptPartCode(
      context,
      title: 'Edit Part',
      moduleLabel: 'Casting',
      codes: codes,
      initialCode: part.part,
      initialMo: part.mo,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.editCastingPart(
        dcm: widget.dcm,
        part: part.part,
        newPart: input.name,
        mo: input.mo,
      ),
    );
  }

  /// Part codes for Casting (from the Parts master), or null after telling the
  /// user why the picker can't open.
  Future<List<PartCode>?> _availableCodes() async {
    try {
      final codes = await _sheetsService.fetchPartCodes('casting');
      if (!mounted) return null;
      if (codes.isEmpty) {
        _snack('No Casting part codes found — import the Parts sheet first.');
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

  Future<void> _deletePart(PartStatus part) async {
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
        module: 'casting',
        kind: 'part',
        group: widget.dcm,
        value: part.part,
      ),
    );
  }

  String _subtitleFor(PartStatus part) {
    final name = part.name;
    final mo = part.mo;
    final updated = part.lastUpdated;
    if (name != null) return mo != null ? 'MO $mo · $name' : name;
    if (mo != null && updated != null) return 'MO $mo · $updated';
    if (mo != null) return 'MO $mo';
    if (updated != null) return 'Last updated: $updated';
    return 'No entries yet · ${widget.shift.toLowerCase()} shift';
  }

  @override
Widget build(BuildContext context) {
    return ModuleScaffold(
      subtitle: 'Casting — ${widget.dcm} · ${widget.shift} shift',
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
        itemCount: _parts.length + 1,
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
            subtitle: _subtitleFor(part),
            icon: Icons.tag_rounded,
            onTap: () => _openPart(part),
            fillPercent: part.fillPercent,
            trailing: CardMenuButton(
              onEdit: () => _editPart(part),
              onDelete: () => _deletePart(part),
            ),
          );
        },
      ),
    );
  }
}
