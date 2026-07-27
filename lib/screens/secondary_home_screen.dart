import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/secondary_models.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
import '../widgets/hicom_app_bar.dart';
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
    final name = await promptText(
      context,
      title: 'Add Station',
      label: 'Station',
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
    final name = await promptText(
      context,
      title: 'Rename Station',
      label: 'Station',
      initialValue: station.station,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HicomAppBar(subtitle: 'Secondary — Stations'),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShiftToggle(shift: _shift, onChanged: _setShift),
                  const SizedBox(height: 14),
                  Text(
                    'Select station',
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
              childAspectRatio: 1.35,
            ),
            itemCount: _stations.length + 1,
            itemBuilder: (context, index) {
              if (index == _stations.length) {
                return AddTile(label: 'Add Station', onTap: _addStation);
              }
              final station = _stations[index];
              return Stack(
                children: [
                  Positioned.fill(
                    child: _StationCard(
                      station: station,
                      onTap: () => _openStation(station),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: CardMenuButton(
                      onEdit: () => _renameStation(station),
                      onDelete: () => _deleteStation(station),
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

class _StationCard extends StatelessWidget {
  const _StationCard({required this.station, required this.onTap});

  final StationStatus station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.handyman_rounded,
                color: AppColors.amber,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                station.station,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                station.lastUpdated != null
                    ? 'Last updated: ${station.lastUpdated}'
                    : 'No entries yet today',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day/Night selector — Secondary runs the same real shift schedule as
/// Casting (Day 8AM-6PM, Night 8PM-6AM crossing midnight), not calendar
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
