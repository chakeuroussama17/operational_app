import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/secondary_models.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
import '../widgets/fill_tank_card.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';
import 'secondary_entry_screen.dart';

/// Part selector for one station: fill-tank cards showing this shift's
/// progress.
class SecondaryPartsScreen extends StatefulWidget {
  const SecondaryPartsScreen({
    super.key,
    required this.station,
    required this.shift,
  });

  final String station;
  final String shift;

  @override
  State<SecondaryPartsScreen> createState() => _SecondaryPartsScreenState();
}

class _SecondaryPartsScreenState extends State<SecondaryPartsScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  List<SecondaryPartStatus> _parts = const [];

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
      final parts = await _sheetsService.fetchSecondaryParts(
        widget.station,
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

  void _openPart(SecondaryPartStatus part) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => SecondaryEntryScreen(
              station: widget.station,
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
    final input = await promptPartWithMo(context, title: 'Add Part');
    if (input == null) return;
    await _mutate(
      () => _sheetsService.addSecondaryPart(
        station: widget.station,
        part: input.name,
        mo: input.mo.isEmpty ? null : input.mo,
      ),
    );
  }

  Future<void> _editPart(SecondaryPartStatus part) async {
    final input = await promptPartWithMo(
      context,
      title: 'Edit Part',
      initialName: part.part,
      initialMo: part.mo,
    );
    if (input == null) return;
    await _mutate(
      () => _sheetsService.editSecondaryPart(
        station: widget.station,
        part: part.part,
        newPart: input.name,
        mo: input.mo,
      ),
    );
  }

  Future<void> _deletePart(SecondaryPartStatus part) async {
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
        module: 'secondary',
        kind: 'part',
        group: widget.station,
        value: part.part,
      ),
    );
  }

  String _subtitleFor(SecondaryPartStatus part) {
    final mo = part.mo;
    final updated = part.lastUpdated;
    if (mo != null && updated != null) return 'MO $mo · $updated';
    if (mo != null) return 'MO $mo';
    if (updated != null) return 'Last updated: $updated';
    return 'No entries yet · ${widget.shift.toLowerCase()} shift';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle: 'Secondary — ${widget.station} · ${widget.shift} shift',
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
          final columns = constraints.maxWidth >= 700
              ? 4
              : constraints.maxWidth >= 480
              ? 3
              : 2;
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimens.screenPadding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppDimens.fieldSpacing,
              crossAxisSpacing: AppDimens.fieldSpacing,
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
                      subtitle: _subtitleFor(part),
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
