import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../services/auth_backend.dart';
import '../services/sheets_service.dart';
import '../widgets/auth_widgets.dart';
import 'signup_screen.dart';

/// Company sign-in: Firebase email + password, restricted to the company
/// domains before Firebase is even called. "Sign up" opens [SignUpScreen],
/// which creates the Firebase account and the Users-tab profile together.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.backend,
    required this.service,
    required this.onSignedIn,
  });

  final AuthBackend backend;
  final SheetsService service;
  final void Function(String email) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;
  String? _passwordError;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  bool _validate() {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });
    var ok = true;
    if (!looksLikeEmail(_email)) {
      setState(() => _emailError = 'Enter a valid email address');
      ok = false;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _passwordError = 'Enter your password');
      ok = false;
    }
    return ok;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
  }

  Future<void> _signIn() async {
    if (!_validate()) return;
    setState(() => _busy = true);
    try {
      final email = await widget.backend.signIn(
        _email,
        _passwordController.text,
      );
      if (!mounted) return;
      widget.onSignedIn(email);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(e.message);
    }
  }

  Future<void> _forgotPassword() async {
    if (!looksLikeEmail(_email)) {
      setState(() => _emailError = 'Enter your email address first');
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
      _showError(e.message);
    }
  }

  Future<void> _openSignUp() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignUpScreen(
          backend: widget.backend,
          service: widget.service,
          onSignedUp: widget.onSignedIn,
        ),
      ),
    );
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
              const SizedBox(height: 44),
              const AuthHeadline(line1: 'Welcome', line2: 'Back!'),
              const SizedBox(height: 34),
              AuthGlassField(
                controller: _emailController,
                hint: 'Email Address',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
              ),
              const SizedBox(height: 16),
              AuthGlassField(
                controller: _passwordController,
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                errorText: _passwordError,
                onSubmitted: (_) => _busy ? null : _signIn(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              AuthGradientButton(
                label: 'LOG IN',
                busy: _busy,
                onPressed: _signIn,
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Don't have an account?  ",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    InkWell(
                      onTap: _busy ? null : _openSignUp,
                      child: const Text(
                        'Sign up',
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
