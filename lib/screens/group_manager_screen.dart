import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/config_models.dart';
import '../services/sheets_service.dart';
import '../widgets/error_retry.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';

/// Add/rename/delete screen for one module's groups (DCM/Station/Customer),
/// their parts, and — for Machining — the global Line list. Reused by all
/// three modules; only the labels and [showLines] differ.
///
/// Deleting or renaming a group cascades to its parts on the backend, but
/// never touches historical rows already logged in the data sheet.
class GroupManagerScreen extends StatefulWidget {
  const GroupManagerScreen({
    super.key,
    required this.module,
    required this.title,
    required this.groupLabel,
    required this.partLabel,
    this.showLines = false,
  });

  final String module;
  final String title;
  final String groupLabel;
  final String partLabel;
  final bool showLines;

  @override
  State<GroupManagerScreen> createState() => _GroupManagerScreenState();
}

class _GroupManagerScreenState extends State<GroupManagerScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  ConfigSnapshot? _snapshot;

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
      final snapshot = await _sheetsService.fetchConfig(widget.module);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
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

  Future<void> _runMutation(Future<void> Function() action) async {
    setState(() => _busy = true);
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGroup() async {
    final name = await promptText(
      context,
      title: 'Add ${widget.groupLabel}',
      label: widget.groupLabel,
    );
    if (name == null) return;
    await _runMutation(
      () => _sheetsService.configAdd(
        module: widget.module,
        kind: 'group',
        value: name,
      ),
    );
  }

  Future<void> _renameGroup(String oldName) async {
    final name = await promptText(
      context,
      title: 'Rename ${widget.groupLabel}',
      label: widget.groupLabel,
      initialValue: oldName,
    );
    if (name == null || name == oldName) return;
    await _runMutation(
      () => _sheetsService.configRename(
        module: widget.module,
        kind: 'group',
        value: oldName,
        newValue: name,
      ),
    );
  }

  Future<void> _deleteGroup(String name) async {
    final parts = _snapshot?.partsByGroup[name] ?? const [];
    final label = widget.partLabel.toLowerCase();
    final confirmed = await confirmDelete(
      context,
      title: 'Delete ${widget.groupLabel} "$name"?',
      message: parts.isEmpty
          ? 'This cannot be undone.'
          : 'This also deletes its ${parts.length} '
                '$label${parts.length == 1 ? '' : 's'} (${parts.join(', ')}). '
                'Historical logs already saved are not affected. '
                'This cannot be undone.',
    );
    if (confirmed != true) return;
    await _runMutation(
      () => _sheetsService.configDelete(
        module: widget.module,
        kind: 'group',
        value: name,
      ),
    );
  }

  Future<void> _addPart(String group) async {
    final name = await promptText(
      context,
      title: 'Add ${widget.partLabel} to $group',
      label: widget.partLabel,
    );
    if (name == null) return;
    await _runMutation(
      () => _sheetsService.configAdd(
        module: widget.module,
        kind: 'part',
        group: group,
        value: name,
      ),
    );
  }

  Future<void> _renamePart(String group, String oldName) async {
    final name = await promptText(
      context,
      title: 'Rename ${widget.partLabel}',
      label: widget.partLabel,
      initialValue: oldName,
    );
    if (name == null || name == oldName) return;
    await _runMutation(
      () => _sheetsService.configRename(
        module: widget.module,
        kind: 'part',
        group: group,
        value: oldName,
        newValue: name,
      ),
    );
  }

  Future<void> _deletePart(String group, String name) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete ${widget.partLabel} "$name"?',
      message:
          'Historical logs already saved are not affected. '
          'This cannot be undone.',
    );
    if (confirmed != true) return;
    await _runMutation(
      () => _sheetsService.configDelete(
        module: widget.module,
        kind: 'part',
        group: group,
        value: name,
      ),
    );
  }

  Future<void> _addLine() async {
    final name = await promptText(
      context,
      title: 'Add Line',
      label: 'Line name',
    );
    if (name == null) return;
    await _runMutation(
      () => _sheetsService.configAdd(
        module: widget.module,
        kind: 'line',
        value: name,
      ),
    );
  }

  Future<void> _renameLine(String oldName) async {
    final name = await promptText(
      context,
      title: 'Rename Line',
      label: 'Line name',
      initialValue: oldName,
    );
    if (name == null || name == oldName) return;
    await _runMutation(
      () => _sheetsService.configRename(
        module: widget.module,
        kind: 'line',
        value: oldName,
        newValue: name,
      ),
    );
  }

  Future<void> _deleteLine(String name) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete Line "$name"?',
      message:
          'Historical logs already saved are not affected. '
          'This cannot be undone.',
    );
    if (confirmed != true) return;
    await _runMutation(
      () => _sheetsService.configDelete(
        module: widget.module,
        kind: 'line',
        value: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(subtitle: widget.title),
      body: SafeArea(child: _body()),
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
    final snapshot = _snapshot!;
    return ListView(
      padding: const EdgeInsets.all(AppDimens.screenPadding),
      children: [
        _SectionHeader(
          title: '${widget.groupLabel}s',
          addLabel: 'Add ${widget.groupLabel}',
          onAdd: _busy ? null : _addGroup,
        ),
        const SizedBox(height: 10),
        if (snapshot.groups.isEmpty)
          _EmptyHint(
            text:
                'No ${widget.groupLabel.toLowerCase()}s yet. '
                'Add one to get started.',
          ),
        for (final group in snapshot.groups)
          _GroupTile(
            group: group,
            parts: snapshot.partsByGroup[group] ?? const [],
            partLabel: widget.partLabel,
            busy: _busy,
            onRenameGroup: () => _renameGroup(group),
            onDeleteGroup: () => _deleteGroup(group),
            onAddPart: () => _addPart(group),
            onRenamePart: (part) => _renamePart(group, part),
            onDeletePart: (part) => _deletePart(group, part),
          ),
        if (widget.showLines) ...[
          const SizedBox(height: 26),
          _SectionHeader(
            title: 'Lines',
            addLabel: 'Add Line',
            onAdd: _busy ? null : _addLine,
          ),
          const SizedBox(height: 10),
          if (snapshot.lines.isEmpty)
            const _EmptyHint(text: 'No lines yet. Add one to get started.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final line in snapshot.lines)
                  _Chip(
                    label: line,
                    busy: _busy,
                    onRename: () => _renameLine(line),
                    onDelete: () => _deleteLine(line),
                  ),
                _AddChip(label: 'Add Line', busy: _busy, onTap: _addLine),
              ],
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------- Presentational widgets ----------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.addLabel,
    required this.onAdd,
  });

  final String title;
  final String addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            addLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.parts,
    required this.partLabel,
    required this.busy,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onAddPart,
    required this.onRenamePart,
    required this.onDeletePart,
  });

  final String group;
  final List<String> parts;
  final String partLabel;
  final bool busy;
  final VoidCallback onRenameGroup;
  final VoidCallback onDeleteGroup;
  final VoidCallback onAddPart;
  final void Function(String part) onRenamePart;
  final void Function(String part) onDeletePart;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          group,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          '${parts.length} $partLabel${parts.length == 1 ? '' : 's'}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 20),
              color: AppColors.steelBlue,
              tooltip: 'Rename',
              onPressed: busy ? null : onRenameGroup,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: AppColors.danger,
              tooltip: 'Delete',
              onPressed: busy ? null : onDeleteGroup,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final part in parts)
                  _Chip(
                    label: part,
                    busy: busy,
                    onRename: () => onRenamePart(part),
                    onDelete: () => onDeletePart(part),
                  ),
                _AddChip(label: 'Add $partLabel', busy: busy, onTap: onAddPart),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.busy,
    required this.onRename,
    required this.onDelete,
  });

  final String label;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 15),
            color: AppColors.steelBlue,
            tooltip: 'Rename',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: busy ? null : onRename,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 15),
            color: AppColors.danger,
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.steelBlue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: AppColors.steelBlue),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.steelBlue,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
