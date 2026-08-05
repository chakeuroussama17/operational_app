import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/app_user.dart';
import '../services/sheets_service.dart';
import '../widgets/auth_widgets.dart';

/// One-time page after the first sign-in: the email is proven (Firebase),
/// this asks who the person actually is — including which department they
/// work in, which is the whole of what they'll be able to see and log — and
/// files them in the Users tab.
///
/// Reached two ways: a Firebase account with no matching sheet row at all
/// (a signup whose profile write failed partway — see [SignUpScreen]), or
/// [existing], a row that predates the Department column and needs just
/// that one field filled in.
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
    return AuthBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AuthLogoLockup(),
              const SizedBox(height: 36),
              AuthHeadline(
                line1: widget.existing == null ? 'Almost' : 'One more',
                line2: widget.existing == null ? 'There!' : 'Thing!',
              ),
              const SizedBox(height: 10),
              Text(
                widget.existing == null
                    ? 'Tell us who you are and where you work — your name '
                          'goes next to every entry you log.'
                    : 'Your account needs a department before you can '
                          'log anything.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.alternate_email,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AuthGlassField(
                controller: _nameController,
                hint: 'Full Name',
                icon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                errorText: _nameError,
              ),
              const SizedBox(height: 14),
              AuthGlassField(
                controller: _idController,
                hint: 'Employee ID',
                icon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.characters,
                errorText: _idError,
                onSubmitted: (_) => _busy ? null : _register(),
              ),
              const SizedBox(height: 14),
              if (_isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.authPink,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Admin — all departments',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                )
              else
                AuthGlassDropdown(
                  hint: 'Department',
                  icon: Icons.apartment_rounded,
                  value: _department,
                  options: departments,
                  errorText: _departmentError,
                  onChanged: (value) => setState(() {
                    _department = value;
                    _departmentError = null;
                  }),
                ),
              const SizedBox(height: 26),
              AuthGradientButton(
                label: 'CONTINUE',
                busy: _busy,
                onPressed: _register,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : widget.onSignOut,
                  child: Text(
                    'Not you? Sign out',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
