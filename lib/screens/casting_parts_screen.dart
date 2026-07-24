import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/casting_models.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/error_retry.dart';
import '../widgets/fill_tank_card.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';
import 'casting_entry_screen.dart';

/// Part selector for one DCM: fill-tank cards showing today's progress.
class CastingPartsScreen extends StatefulWidget {
  const CastingPartsScreen({super.key, required this.dcm});

  final String dcm;

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
      final parts = await _sheetsService.fetchCastingParts(widget.dcm);
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
            builder: (_) =>
                CastingEntryScreen(dcm: widget.dcm, part: part.part),
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
    final name = await promptText(context, title: 'Add Part', label: 'Part');
    if (name == null) return;
    await _mutate(
      () => _sheetsService.configAdd(
        module: 'casting',
        kind: 'part',
        group: widget.dcm,
        value: name,
      ),
    );
  }

  Future<void> _managePart(PartStatus part) async {
    final action = await showManageActionSheet(
      context,
      itemLabel: 'Part ${part.part}',
    );
    if (action == null || !mounted) return;
    if (action == ManageAction.rename) {
      final name = await promptText(
        context,
        title: 'Rename Part',
        label: 'Part',
        initialValue: part.part,
      );
      if (name == null || name == part.part) return;
      await _mutate(
        () => _sheetsService.configRename(
          module: 'casting',
          kind: 'part',
          group: widget.dcm,
          value: part.part,
          newValue: name,
        ),
      );
    } else {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(subtitle: 'Casting — DCM ${widget.dcm}'),
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
                    SizedBox(height: 2),
                    Text(
                      'Tap to log · long-press a card to rename or delete',
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
              return FillTankCard(
                title: part.part,
                subtitle: part.lastUpdated != null
                    ? 'Last updated: ${part.lastUpdated}'
                    : 'No entries yet today',
                fillPercent: part.fillPercent,
                onTap: () => _openPart(part),
                onLongPress: () => _managePart(part),
              );
            },
          );
        },
      ),
    );
  }
}
