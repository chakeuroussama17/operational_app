import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/secondary_models.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/error_retry.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';
import 'group_manager_screen.dart';
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
      final stations = await _sheetsService.fetchSecondaryDashboard();
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

  void _openStation(StationStatus station) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => SecondaryPartsScreen(station: station.station),
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

  Future<void> _manageStation(StationStatus station) async {
    final action = await showManageActionSheet(
      context,
      itemLabel: 'Station ${station.station}',
    );
    if (action == null || !mounted) return;
    if (action == ManageAction.rename) {
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
    } else {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle: 'Secondary — Stations',
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Manage stations & parts',
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GroupManagerScreen(
                        module: 'secondary',
                        title: 'Manage — Secondary',
                        groupLabel: 'Station',
                        partLabel: 'Part',
                      ),
                    ),
                  )
                  .then((_) => _load());
            },
          ),
        ],
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
                      'Select station',
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
              return _StationCard(
                station: station,
                onTap: () => _openStation(station),
                onLongPress: () => _manageStation(station),
              );
            },
          );
        },
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.onTap,
    required this.onLongPress,
  });

  final StationStatus station;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
        onLongPress: onLongPress,
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
