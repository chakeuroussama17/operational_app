import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config/constants.dart';
import '../models/raw_table.dart';
import '../models/sheet_export.dart';
import '../services/sheets_service.dart';
import '../widgets/error_retry.dart';

/// The sheet, unaggregated.
///
/// Every other screen in the app either writes one row or summarises many.
/// This one shows a tab as it actually is, so a supervisor can check a
/// specific entry — which hour a rejection landed in, what MO a part ran
/// under — without leaving for the spreadsheet.
///
/// Rows arrive newest-first and capped by the backend; these tabs grow
/// without bound and a full year of them would never finish loading on a
/// connection that already costs seconds per call.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key, this.modules = const [], this.service});

  /// Which departments this person may look at. Empty means no restriction.
  final List<String> modules;

  /// Test seam, same as the other screens.
  final SheetsService? service;

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late final _sheetsService = widget.service ?? SheetsService();
  late final List<RawTabRef> _tabs = rawTabsFor(widget.modules);

  late RawTabRef _selected = _tabs.first;
  RawTable? _table;
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _sheetsService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final table = await _sheetsService.fetchRawTab(_selected.name);
      if (!mounted) return;
      setState(() {
        _table = table;
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

  void _select(RawTabRef tab) {
    if (tab.name == _selected.name) return;
    setState(() {
      _selected = tab;
      _table = null;
      _query = '';
    });
    _load();
  }

  /// Download: pick the window first, because a month of a busy tab is a
  /// different fetch from what the screen is already showing.
  Future<void> _chooseRange() async {
    final choice = await showModalBottomSheet<ExportRange>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.download_rounded, color: AppColors.navy, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Download ${_selected.title}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            _RangeTile(
              icon: Icons.today_rounded,
              title: 'Today',
              subtitle: 'Just this shift-day',
              onTap: () => Navigator.of(sheetContext).pop(ExportRange.today),
            ),
            _RangeTile(
              icon: Icons.calendar_month_rounded,
              title: 'This month',
              subtitle: 'The 1st to today',
              onTap: () => Navigator.of(sheetContext).pop(ExportRange.month),
            ),
            _RangeTile(
              icon: Icons.date_range_rounded,
              title: 'Custom range',
              subtitle: 'Pick the two dates',
              onTap: () => Navigator.of(sheetContext).pop(ExportRange.custom),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    var window = DateWindow.forRange(choice, DateTime.now());
    if (choice == ExportRange.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        ),
      );
      if (picked == null || !mounted) return;
      window = DateWindow(picked.start, picked.end);
    }
    await _export(window);
  }

  Future<void> _export(DateWindow window) async {
    setState(() => _exporting = true);
    try {
      // Refetch rather than export what is on screen: the browse view holds
      // the newest 300, and a month of a busy tab runs past that. The
      // backend's own ceiling is what caps this.
      final full = await _sheetsService.fetchRawTab(_selected.name, limit: 2000);
      final rows = rowsInWindow(full, window);
      if (!mounted) return;

      if (rows.isEmpty) {
        setState(() => _exporting = false);
        _snack('No rows in ${_selected.title} for that range.');
        return;
      }

      final csv = toCsv(full.cols, rows);
      final name = exportFileName(_selected.name, window);
      // UTF-8 with a BOM: without it Excel opens the file in the local
      // codepage and mangles any non-ASCII part name.
      final bytes = Uint8List.fromList(
        [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)],
      );

      // Bytes rather than a file on disk, deliberately: share_plus writes
      // its own temp file on Android and hands the browser a download on
      // web, so this one path works for the APK and the web build alike.
      // Touching dart:io here would compile but break the web build at the
      // moment someone pressed Download.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'text/csv', name: name)],
          fileNameOverrides: [name],
          subject: name,
          text: '${_selected.title} — ${rows.length} rows (${window.label})',
        ),
      );
      if (!mounted) return;
      setState(() => _exporting = false);
    } on SheetsSubmissionException catch (error) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _snack(error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _snack('Could not build the file: $error');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Rows matching the search, across every column — the whole point is to
  /// find one row without knowing which column holds the thing you typed.
  List<List<String>> get _rows {
    final table = _table;
    if (table == null) return const [];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return table.rows;
    return table.rows
        .where((r) => r.any((c) => c.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(tabs: _tabs, selected: _selected, onSelect: _select),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.screenPadding,
            4,
            AppDimens.screenPadding,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search this tab',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _query = ''),
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 10),
              _DownloadButton(
                busy: _exporting,
                onPressed: _exporting ? null : _chooseRange,
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.steelBlue),
      );
    }
    if (_error != null) return ErrorRetry(message: _error!, onRetry: _load);

    final table = _table;
    if (table == null || table.cols.isEmpty) {
      return const _Empty(text: 'That tab has no columns yet.');
    }
    final rows = _rows;
    if (rows.isEmpty) {
      return _Empty(
        text: _query.isEmpty
            ? 'Nothing logged in this tab yet.'
            : 'No row matches “$_query”.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.screenPadding,
            0,
            AppDimens.screenPadding,
            8,
          ),
          child: Text(
            _countLine(table, rows.length),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.steelBlue,
            onRefresh: _load,
            // Two scroll axes: the tab is far wider than a phone, and the
            // vertical one has to stay a ListView-style scrollable for
            // pull-to-refresh to have something to attach to.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: _DataGrid(cols: table.cols, rows: rows),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _countLine(RawTable table, int shown) {
    final filtered = _query.trim().isNotEmpty;
    if (filtered) return '$shown of ${table.rows.length} rows match';
    if (table.isCapped) {
      return 'Newest ${table.rows.length} of ${table.total} rows · '
          '${table.cols.length} columns';
    }
    return '${table.rows.length} row${table.rows.length == 1 ? '' : 's'} · '
        '${table.cols.length} columns';
  }
}

/// Horizontally scrolling tab chips — there are up to seven and they must
/// not wrap into a block that eats the screen on a phone.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<RawTabRef> tabs;
  final RawTabRef selected;
  final ValueChanged<RawTabRef> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.screenPadding,
          vertical: 6,
        ),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final isSelected = tab.name == selected.name;
          return ChoiceChip(
            label: Text(tab.title),
            selected: isSelected,
            onSelected: (_) => onSelect(tab),
            showCheckmark: false,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            selectedColor: AppColors.navy,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: isSelected ? AppColors.navy : AppColors.borderSubtle,
            ),
          );
        },
      ),
    );
  }
}

/// The grid itself. Hand-built rather than DataTable: DataTable sizes every
/// column to its widest cell and offers no sticky header, which on a
/// 32-column machining tab produces a grid nobody can navigate.
class _DataGrid extends StatelessWidget {
  const _DataGrid({required this.cols, required this.rows});

  final List<String> cols;
  final List<List<String>> rows;

  static const double _cellWidth = 118;
  static const double _firstWidth = 104;

  double _widthFor(int i) => i == 0 ? _firstWidth : _cellWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cols.length; i++)
                SizedBox(
                  width: _widthFor(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Text(
                      cols[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var r = 0; r < rows.length; r++)
          Container(
            color: r.isEven ? Colors.transparent : AppColors.surfaceTint
                .withValues(alpha: 0.45),
            child: Row(
              children: [
                for (var i = 0; i < cols.length; i++)
                  SizedBox(
                    width: _widthFor(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      child: Text(
                        // A blank cell reads as an em dash, so an empty
                        // column is visibly empty rather than ambiguous.
                        i < rows[r].length && rows[r][i].trim().isNotEmpty
                            ? rows[r][i]
                            : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: i < rows[r].length &&
                                  rows[r][i].trim().isNotEmpty
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Deliberately a labelled button rather than a bare icon: downloading is
/// the one destructive-feeling action here (it leaves the app), and it
/// should be obvious what it does before it is pressed.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(busy ? 'Preparing' : 'Download'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _RangeTile extends StatelessWidget {
  const _RangeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.steelBlue),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
      ),
    );
  }
}
