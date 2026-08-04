import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/app_user.dart';
import '../services/sheets_service.dart';

/// One-time page after the first sign-in: the email is proven (Firebase),
/// this asks who the person actually is — including which department they
/// work in, which is the whole of what they'll be able to see and log — and
/// files them in the Users tab.
///
/// Also the repair path for an account registered before departments existed:
/// pass [existing] and it prefills, asking only for the missing department.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.email,
    required this.service,
    required this.onRegistered,
    required this.onSignOut,
    this.existing,
  });

  final String email;
  final SheetsService service;
  final void Function(AppUser user) onRegistered;
  final VoidCallback onSignOut;

  /// Non-null when the account is already on the sheet but has no department.
  final AppUser? existing;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _idController = TextEditingController(
    text: widget.existing?.employeeId ?? '',
  );
  String? _department;
  String? _nameError;
  String? _idError;
  String? _departmentError;
  bool _busy = false;

  /// The admin owns every department, so there is nothing to choose.
  bool get _isAdmin => widget.email.trim().toLowerCase() == adminEmail;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final id = _idController.text.trim();
    final department = _isAdmin ? 'All' : _department;
    setState(() {
      _nameError = name.isEmpty ? 'Enter your full name' : null;
      _idError = id.isEmpty ? 'Enter your employee ID' : null;
      _departmentError = department == null ? 'Choose your department' : null;
    });
    if (name.isEmpty || id.isEmpty || department == null) return;

    setState(() => _busy = true);
    try {
      final user = await widget.service.registerUser(
        email: widget.email,
        name: name,
        employeeId: id,
        department: department,
      );
      if (!mounted) return;
      widget.onRegistered(user);
    } on SheetsSubmissionException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.badge_outlined, size: 52, color: AppColors.navy),
                  const SizedBox(height: 12),
                  Text(
                    widget.existing == null ? 'Almost there' : 'One more thing',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.existing == null
                        ? 'Tell us who you are and where you work — your name '
                              'goes next to every entry you log.'
                        : 'Your account needs a department before you can '
                              'log anything.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alternate_email, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _idController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Employee ID',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      errorText: _idError,
                    ),
                    onSubmitted: (_) => _busy ? null : _register(),
                  ),
                  const SizedBox(height: 18),
                  _DepartmentPicker(
                    isAdmin: _isAdmin,
                    selected: _department,
                    error: _departmentError,
                    onSelected: (value) => setState(() {
                      _department = value;
                      _departmentError = null;
                    }),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _register,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'REGISTER',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : widget.onSignOut,
                    child: const Text('Not you? Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which department this person works in — the one thing here they cannot
/// change later on their own, since it decides what they can see and log.
class _DepartmentPicker extends StatelessWidget {
  const _DepartmentPicker({
    required this.isAdmin,
    required this.selected,
    required this.error,
    required this.onSelected,
  });

  final bool isAdmin;
  final String? selected;
  final String? error;
  final ValueChanged<String> onSelected;

  static const _icons = {
    'Casting': Icons.local_fire_department_rounded,
    'Secondary': Icons.handyman_rounded,
    'Machining': Icons.precision_manufacturing_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (isAdmin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.navy.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: 20,
              color: AppColors.navy,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Admin — all departments',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Department',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        for (final department in departments) ...[
          _DepartmentOption(
            label: department,
            icon: _icons[department] ?? Icons.factory_rounded,
            selected: selected == department,
            onTap: () => onSelected(department),
          ),
          const SizedBox(height: 8),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              error!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ),
      ],
    );
  }
}

class _DepartmentOption extends StatelessWidget {
  const _DepartmentOption({
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? AppColors.navy : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.navy : AppColors.textPrimary,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 22, color: AppColors.navy),
          ],
        ),
      ),
    );
  }
}
