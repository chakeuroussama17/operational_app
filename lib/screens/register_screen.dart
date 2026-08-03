import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/app_user.dart';
import '../services/sheets_service.dart';

/// One-time page after the first sign-in: the email is proven (Firebase),
/// this asks who the person actually is and files them in the Users tab.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.email,
    required this.service,
    required this.onRegistered,
    required this.onSignOut,
  });

  final String email;
  final SheetsService service;
  final void Function(AppUser user) onRegistered;
  final VoidCallback onSignOut;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  String? _nameError;
  String? _idError;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final id = _idController.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Enter your full name' : null;
      _idError = id.isEmpty ? 'Enter your employee ID' : null;
    });
    if (name.isEmpty || id.isEmpty) return;

    setState(() => _busy = true);
    try {
      final user = await widget.service.registerUser(
        email: widget.email,
        name: name,
        employeeId: id,
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
                    'Almost there',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tell us who you are — this is shown next to every '
                    'entry you log.',
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
