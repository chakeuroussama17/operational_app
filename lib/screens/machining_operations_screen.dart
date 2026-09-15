import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/machining_models.dart';
import '../widgets/module_shell.dart';
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
    return ModuleScaffold(
      subtitle: 'Machining — Operation',
      leading: ShiftToggle(
        shift: _shift,
        onChanged: (shift) => setState(() => _shift = shift),
      ),
      headline: 'Select operation',
      hint: 'Then the customer, then the part',
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.screenPadding,
          4,
          AppDimens.screenPadding,
          28,
        ),
        itemCount: machiningOperations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final operation = machiningOperations[index];
          return SelectorCard(
            title: operation.label,
            subtitle: operation.description,
            icon: index == 0
                ? Icons.precision_manufacturing_rounded
                : Icons.handyman_rounded,
            onTap: () => _openOperation(operation),
          );
        },
      ),
    );
  }
}

/// Day/Night selector — Machining runs the same real shift schedule as the
/// other modules (Day 10AM-8PM, Night 10PM-8AM crossing midnight), not calendar
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
