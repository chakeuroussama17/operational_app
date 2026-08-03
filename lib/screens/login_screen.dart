import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../services/auth_backend.dart';

/// Company sign-in: Firebase email + password, restricted to the company
/// domains before Firebase is even called. CREATE ACCOUNT is the same form —
/// first-timers make their Firebase account here, then the gate sends them to
/// the one-time registration page (name + employee ID).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.backend,
    required this.onSignedIn,
  });

  final AuthBackend backend;
  final void Function(String email) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;
  String? _passwordError;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  bool _validate({required bool forCreate}) {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });
    var ok = true;
    if (!allowedEmailDomains.any(_email.endsWith)) {
      setState(
        () => _emailError =
            'Use your company email (${allowedEmailDomains.join(' or ')})',
      );
      ok = false;
    }
    if (forCreate && _passwordController.text.length < 6) {
      setState(() => _passwordError = 'At least 6 characters');
      ok = false;
    } else if (_passwordController.text.isEmpty) {
      setState(() => _passwordError = 'Enter your password');
      ok = false;
    }
    return ok;
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final email = await action();
      if (!mounted) return;
      widget.onSignedIn(email);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
    }
  }

  void _signIn() {
    if (!_validate(forCreate: false)) return;
    _run(() => widget.backend.signIn(_email, _passwordController.text));
  }

  void _createAccount() {
    if (!_validate(forCreate: true)) return;
    _run(() => widget.backend.createAccount(_email, _passwordController.text));
  }

  Future<void> _forgotPassword() async {
    if (!allowedEmailDomains.any(_email.endsWith)) {
      setState(() => _emailError = 'Enter your company email first');
      return;
    }
    try {
      await widget.backend.sendPasswordReset(_email);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
    } on AuthFailure catch (e) {
      if (!mounted) return;
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
                  Icon(Icons.factory_rounded, size: 56, color: AppColors.navy),
                  const SizedBox(height: 12),
                  Text(
                    'HICOM DIECASTINGS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    'Production shift log',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 34),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Company email',
                      prefixIcon: const Icon(Icons.alternate_email),
                      errorText: _emailError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _passwordError,
                    ),
                    onSubmitted: (_) => _busy ? null : _signIn(),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
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
                            'SIGN IN',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : _createAccount,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'CREATE ACCOUNT',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: const Text('Forgot password?'),
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
