import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../services/sheets_service.dart';
import '../widgets/module_shell.dart';
import 'auth_gate.dart';
import '../widgets/card_menu_button.dart';
import '../widgets/error_retry.dart';
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
      subtitle: 'Machining — ${widget.operation.label} · ${widget.shift} shift',
      headline: 'Select customer',
      hint: 'Tap to open · ⋮ to rename or delete',
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
        itemCount: _customers.length + (_canManage ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _customers.length) {
            return SizedBox(
              height: 88,
              child: AddCard(label: 'Add customer', onTap: _addCustomer),
            );
          }
          final customer = _customers[index];
          return SelectorCard(
            title: customer.customer,
            subtitle: customer.lastUpdated != null
                ? 'Last updated ${customer.lastUpdated}'
                : 'No entries yet this shift',
            icon: Icons.factory_rounded,
            onTap: () => _openCustomer(customer),
            trailing: !_canManage
                ? null
                : CardMenuButton(
              onEdit: () => _renameCustomer(customer),
              onDelete: () => _deleteCustomer(customer),
            ),
          );
        },
      ),
    );
  }
}
