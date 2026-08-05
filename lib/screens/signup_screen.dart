import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../services/auth_backend.dart';
import '../services/sheets_service.dart';
import '../widgets/auth_widgets.dart';

/// Create an account: one screen, but two things happen underneath — the
/// Firebase account (proves the email is real) and the Users-tab profile
/// (name, employee ID, department) get created back to back on the same tap.
///
/// If the profile write fails after the Firebase account succeeds (a
/// network blip between the two calls), nothing is lost: the next sign-in
/// finds a Firebase account with no matching profile and [AuthGate] routes
/// to the plain registration screen to finish the second half — the account
/// itself is never in a half-created state from the user's point of view.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    super.key,
    required this.backend,
    required this.service,
    required this.onSignedUp,
  });

  final AuthBackend backend;
  final SheetsService service;
  final void Function(String email) onSignedUp;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _idController = TextEditingController();

  String? _department;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _idError;
  String? _departmentError;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _idController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  /// The admin owns every department, so the picker never asks.
  bool get _isAdmin => _email == adminEmail;

  bool _validate() {
    setState(() {
      _nameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmError = null;
      _idError = null;
      _departmentError = null;
    });

    var ok = true;
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter your full name');
      ok = false;
    }
    if (!allowedEmailDomains.any(_email.endsWith)) {
      setState(
        () => _emailError =
            'Use your company email (${allowedEmailDomains.join(' or ')})',
      );
      ok = false;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _passwordError = 'At least 6 characters');
      ok = false;
    }
    if (_confirmController.text != _passwordController.text ||
        _confirmController.text.isEmpty) {
      setState(() => _confirmError = 'Passwords don\'t match');
      ok = false;
    }
    if (_idController.text.trim().isEmpty) {
      setState(() => _idError = 'Enter your employee ID');
      ok = false;
    }
    if (!_isAdmin && _department == null) {
      setState(() => _departmentError = 'Choose your department');
      ok = false;
    }
    return ok;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _busy = true);

    final email = _email;
    try {
      await widget.backend.createAccount(email, _passwordController.text);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(e.message);
      return;
    }

    try {
      await widget.service.registerUser(
        email: email,
        name: _nameController.text.trim(),
        employeeId: _idController.text.trim(),
        department: _isAdmin ? 'All' : _department!,
      );
      if (!mounted) return;
      widget.onSignedUp(email);
    } on SheetsSubmissionException catch (e) {
      // The Firebase account exists now even though the profile didn't save
      // — say so plainly rather than implying nothing happened, since a
      // second tap would try (and fail) to recreate the same account.
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(
        'Your account was created, but saving your details failed: '
        '${e.message}. Sign in and it will pick up where this left off.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 12, 26, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const AuthHeadline(line1: 'Create an', line2: 'Account!'),
              const SizedBox(height: 28),
              AuthGlassField(
                controller: _nameController,
                hint: 'Full Name',
                icon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                errorText: _nameError,
              ),
              const SizedBox(height: 14),
              AuthGlassField(
                controller: _emailController,
                hint: 'Email Address',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
              ),
              const SizedBox(height: 14),
              AuthGlassField(
                controller: _passwordController,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                errorText: _passwordError,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AuthGlassField(
                controller: _confirmController,
                hint: 'Confirm Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirm,
                errorText: _confirmError,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AuthGlassField(
                controller: _idController,
                hint: 'Employee ID',
                icon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.characters,
                errorText: _idError,
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
                label: 'SIGN UP',
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 22),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Already have an account?  ',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    InkWell(
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.authPink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
