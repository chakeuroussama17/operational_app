import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../widgets/hicom_app_bar.dart';
import 'machining_home_screen.dart';

/// Machining module root: pick the operation being logged, then the shift.
///
/// Operation used to be the LAST selector (called "Line", chosen after the
/// part); it is first now because it splits the plant in two — a machining
/// supervisor never wants to scroll past assembly customers to reach theirs.
///
/// Deliberately makes no network call: the plant runs exactly two operations,
/// so they ship with the app and this screen opens instantly. The first fetch
/// happens one level down, already scoped to the chosen operation.
class MachiningOperationsScreen extends StatefulWidget {
  const MachiningOperationsScreen({super.key});

  @override
  State<MachiningOperationsScreen> createState() =>
      _MachiningOperationsScreenState();
}

class _MachiningOperationsScreenState extends State<MachiningOperationsScreen> {
  /// Defaults to whatever shift wall-clock time suggests; the supervisor can
  /// flip it any time (e.g. logging a late entry after shift changeover).
  /// Owned here, at the root, and passed down to every screen below.
  String _shift = autoDetectMachiningShift();

  void _openOperation(MachiningOperation operation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MachiningHomeScreen(operation: operation, shift: _shift),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HicomAppBar(subtitle: 'Machining — Operation'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  ShiftToggle(
                    shift: _shift,
                    onChanged: (shift) => setState(() => _shift = shift),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Select operation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Then the customer, then the part',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppDimens.screenPadding),
                itemCount: machiningOperations.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppDimens.fieldSpacing),
                itemBuilder: (context, index) {
                  final operation = machiningOperations[index];
                  return _OperationCard(
                    operation: operation,
                    icon: index == 0
                        ? Icons.precision_manufacturing_rounded
                        : Icons.handyman_rounded,
                    onTap: () => _openOperation(operation),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.operation,
    required this.icon,
    required this.onTap,
  });

  final MachiningOperation operation;
  final IconData icon;
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppColors.authGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      operation.label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      operation.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day/Night selector — Machining runs the same real shift schedule as the
/// other modules (Day 8AM-6PM, Night 8PM-6AM crossing midnight), not calendar
/// midnight. Everything below this screen operates within the selected shift.
class ShiftToggle extends StatelessWidget {
  const ShiftToggle({super.key, required this.shift, required this.onChanged});

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
