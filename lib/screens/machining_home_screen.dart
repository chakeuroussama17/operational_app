import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../services/sheets_service.dart';
import '../widgets/add_tile.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
import '../widgets/hicom_app_bar.dart';
import '../widgets/manage_dialogs.dart';
import 'machining_parts_screen.dart';

/// Customer selector (Mazda, Proton, Toyota) for one operation. Second step
/// of the module now — [MachiningOperationsScreen] picks the operation and the
/// shift above it, and both are carried down to the entry form.
class MachiningHomeScreen extends StatefulWidget {
  const MachiningHomeScreen({
    super.key,
    required this.operation,
    required this.shift,
  });

  final MachiningOperation operation;
  final String shift;

  @override
  State<MachiningHomeScreen> createState() => _MachiningHomeScreenState();
}

class _MachiningHomeScreenState extends State<MachiningHomeScreen> {
  final _sheetsService = SheetsService();

  bool _loading = true;
  String? _error;
  List<CustomerStatus> _customers = const [];

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
      final customers = await _sheetsService.fetchMachiningDashboard(
        shift: widget.shift,
        operation: widget.operation.value,
      );
      if (!mounted) return;
      setState(() {
        _customers = customers;
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

  void _openCustomer(CustomerStatus customer) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => MachiningPartsScreen(
              customer: customer.customer,
              operation: widget.operation,
              shift: widget.shift,
            ),
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

  Future<void> _addCustomer() async {
    final name = await promptText(
      context,
      title: 'Add Customer',
      label: 'Customer',
    );
    if (name == null) return;
    await _mutate(
      () => _sheetsService.configAdd(
        module: 'machining',
        kind: 'group',
        value: name,
      ),
    );
  }

  Future<void> _renameCustomer(CustomerStatus customer) async {
    final name = await promptText(
      context,
      title: 'Rename Customer',
      label: 'Customer',
      initialValue: customer.customer,
    );
    if (name == null || name == customer.customer) return;
    await _mutate(
      () => _sheetsService.configRename(
        module: 'machining',
        kind: 'group',
        value: customer.customer,
        newValue: name,
      ),
    );
  }

  Future<void> _deleteCustomer(CustomerStatus customer) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete Customer ${customer.customer}?',
      message:
          'This also deletes all of its parts. Historical logs already '
          'saved are not affected. This cannot be undone.',
    );
    if (confirmed != true) return;
    await _mutate(
      () => _sheetsService.configDelete(
        module: 'machining',
        kind: 'group',
        value: customer.customer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HicomAppBar(
        subtitle:
            'Machining — ${widget.operation.label} · ${widget.shift} shift',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select customer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to open · ⋮ to rename or delete',
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
            itemCount: _customers.length + 1,
            itemBuilder: (context, index) {
              if (index == _customers.length) {
                return AddTile(label: 'Add Customer', onTap: _addCustomer);
              }
              final customer = _customers[index];
              return Stack(
                children: [
                  Positioned.fill(
                    child: _CustomerCard(
                      customer: customer,
                      onTap: () => _openCustomer(customer),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: CardMenuButton(
                      onEdit: () => _renameCustomer(customer),
                      onDelete: () => _deleteCustomer(customer),
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

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final CustomerStatus customer;
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
                Icons.precision_manufacturing_rounded,
                color: AppColors.amber,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                customer.customer,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                customer.lastUpdated != null
                    ? 'Last updated: ${customer.lastUpdated}'
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
