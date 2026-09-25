import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/secondary_models.dart';
import '../services/sheets_service.dart';
import '../widgets/module_shell.dart';
import 'auth_gate.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
import '../widgets/manage_dialogs.dart';
import 'secondary_parts_screen.dart';

/// Secondary module root: pick a station (ST1, ST2, ST3).
class SecondaryHomeScreen extends StatefulWidget {
  const SecondaryHomeScreen({super.key});

  @override
  State<SecondaryHomeScreen> createState() => _SecondaryHomeScreenState();
}

class _SecondaryHomeScreenState extends State<SecondaryHomeScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  List<StationStatus> _stations = const [];

  /// Defaults to whatever shift wall-clock time suggests; the supervisor can
  /// flip it any time (e.g. logging a late entry after shift changeover).
  String _shift = autoDetectSecondaryShift();

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
      final stations = await _sheetsService.fetchSecondaryDashboard(
        shift: _shift,
      );
      if (!mounted) return;
      setState(() {
        _stations = stations;
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

  void _setShift(String shift) {
    if (shift == _shift) return;
    setState(() => _shift = shift);
    _load();
  }

  void _openStation(StationStatus station) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SecondaryPartsScreen(station: station.station, shift: _shift),
          ),
        )
        // Refresh timestamps after logging deeper in the flow.
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

  Future<void> _addStation() async {
    final name = await promptFromList(
      context,
      title: 'Add station',
      options: secondaryStations,
      // Stations already on the grid stay listed but greyed, so a full list
      // reads as "all present" rather than "the list is broken".
      taken: {for (final s in _stations) s.station},
    );
    if (name == null) return;
    await _mutate(
      () => _sheetsService.configAdd(
        module: 'secondary',
        kind: 'group',
        value: name,
      ),
    );
  }

  Future<void> _renameStation(StationStatus station) async {
    final name = await promptFromList(
      context,
      title: 'Change station',
      options: secondaryStations,
      initialValue: station.station,
      taken: {for (final s in _stations) s.station},
    );
    if (name == null || name == station.station) return;
    await _mutate(
      () => _sheetsService.configRename(
        module: 'secondary',
        kind: 'group',
        value: station.station,
        newValue: name,
      ),
    );
  }

  Future<void> _deleteStation(StationStatus station) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete Station ${station.station}?',
      message:
          'This also deletes all of its parts. Historical logs already '
          'saved are not affected. This cannot be undone.',
    );
    if (confirmed != true) return;
    await _mutate(
      () => _sheetsService.configDelete(
        module: 'secondary',
        kind: 'group',
        value: station.station,
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
      subtitle: 'Secondary — Stations',
      leading: _ShiftToggle(shift: _shift, onChanged: _setShift),
      headline: 'Select station',
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
        itemCount: _stations.length + (_canManage ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _stations.length) {
            return SizedBox(
              height: 88,
              child: AddCard(label: 'Add station', onTap: _addStation),
            );
          }
          final station = _stations[index];
          return SelectorCard(
            title: station.station,
            subtitle: station.lastUpdated != null
                ? 'Last updated ${station.lastUpdated}'
                : 'No entries yet this shift',
            icon: Icons.handyman_rounded,
            onTap: () => _openStation(station),
            trailing: !_canManage
                ? null
                : CardMenuButton(
              onEdit: () => _renameStation(station),
              onDelete: () => _deleteStation(station),
            ),
          );
        },
      ),
    );
  }
}

/// Day/Night selector — Secondary runs the same real shift schedule as
/// Casting (Day 10AM-8PM, Night 10PM-8AM crossing midnight), not calendar
/// midnight. Everything below this screen operates within the selected shift.
class _ShiftToggle extends StatelessWidget {
  const _ShiftToggle({required this.shift, required this.onChanged});

  final String shift;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ShiftButton(
            label: 'Day shift',
            icon: Icons.wb_sunny_rounded,
            selected: shift == 'Day',
            onTap: () => onChanged('Day'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ShiftButton(
            label: 'Night shift',
            icon: Icons.nightlight_round,
            selected: shift == 'Night',
            onTap: () => onChanged('Night'),
          ),
        ),
      ],
    );
  }
}

class _ShiftButton extends StatelessWidget {
  const _ShiftButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.amber : AppColors.steelBlue,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.steelBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
