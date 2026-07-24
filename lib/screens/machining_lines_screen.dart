import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/error_retry.dart';
import '../widgets/fill_tank_card.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';
import 'machining_entry_screen.dart';

/// Line selector for one customer + part: fill-tank cards showing today's
/// progress. This is the level that opens the entry form. Lines are a
/// global list (not tied to a customer/part), added/renamed/deleted with no
/// [group] argument.
class MachiningLinesScreen extends StatefulWidget {
  const MachiningLinesScreen({
    super.key,
    required this.customer,
    required this.part,
  });

  final String customer;
  final String part;

  @override
  State<MachiningLinesScreen> createState() => _MachiningLinesScreenState();
}

class _MachiningLinesScreenState extends State<MachiningLinesScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  List<MachiningLineStatus> _lines = const [];

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
      final lines = await _sheetsService.fetchMachiningLines(
        customer: widget.customer,
        part: widget.part,
      );
      if (!mounted) return;
      setState(() {
        _lines = lines;
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

  void _openLine(MachiningLineStatus line) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => MachiningEntryScreen(
              customer: widget.customer,
              part: widget.part,
              line: line.line,
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

  Future<void> _addLine() async {
    final name = await promptText(context, title: 'Add Line', label: 'Line');
    if (name == null) return;
    await _mutate(
      () => _sheetsService.configAdd(
        module: 'machining',
        kind: 'line',
        value: name,
      ),
    );
  }

  Future<void> _manageLine(MachiningLineStatus line) async {
    final action = await showManageActionSheet(context, itemLabel: line.line);
    if (action == null || !mounted) return;
    if (action == ManageAction.rename) {
      final name = await promptText(
        context,
        title: 'Rename Line',
        label: 'Line',
        initialValue: line.line,
      );
      if (name == null || name == line.line) return;
      await _mutate(
        () => _sheetsService.configRename(
          module: 'machining',
          kind: 'line',
          value: line.line,
          newValue: name,
        ),
      );
    } else {
      final confirmed = await confirmDelete(
        context,
        title: 'Delete Line ${line.line}?',
        message:
            'This removes it from every customer/part. Historical logs '
            'already saved are not affected. This cannot be undone.',
      );
      if (confirmed != true) return;
      await _mutate(
        () => _sheetsService.configDelete(
          module: 'machining',
          kind: 'line',
          value: line.line,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle: 'Machining — ${widget.customer} · Part ${widget.part}',
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
                      'Select line',
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
            itemCount: _lines.length + 1,
            itemBuilder: (context, index) {
              if (index == _lines.length) {
                return AddTile(label: 'Add Line', onTap: _addLine);
              }
              final line = _lines[index];
              return FillTankCard(
                title: line.line,
                subtitle: line.lastUpdated != null
                    ? 'Last updated: ${line.lastUpdated}'
                    : 'No entries yet today',
                fillPercent: line.fillPercent,
                onTap: () => _openLine(line),
                onLongPress: () => _manageLine(line),
              );
            },
          );
        },
      ),
    );
  }
}
