import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../firebase_options.dart';
import '../models/app_user.dart';
import '../services/auth_backend.dart';
import '../services/sheets_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Lets screens deeper in the tree (the app bar) offer "sign out" without
/// being wired to the gate directly.
class AuthScope extends InheritedWidget {
  const AuthScope({
    super.key,
    required this.user,
    required this.signOut,
    required super.child,
  });

  final AppUser user;
  final VoidCallback signOut;

  static AuthScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>();

  /// Pops back to the root first — pushed screens must not outlive the
  /// session they were opened in.
  static void signOutFrom(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    scope.signOut();
  }

  @override
  bool updateShouldNotify(AuthScope oldWidget) =>
      user.email != oldWidget.user.email;
}

enum _GateState {
  initializing,
  notConfigured,
  loggedOut,
  checking,
  register,
  /// Just registered, and the Users row came back inactive — every new sign-up
  /// does, since any email may register now and the admin decides who is real.
  pendingApproval,
  blocked,
  checkFailed,
  ready,
}

/// The front door: Firebase proves the email, the Users tab decides whether
/// that person may enter (registered AND active). The sheet is re-checked on
/// every app start, so deactivating someone in the Users tab locks them out
/// the next time the app opens — and the backend refuses their writes even
/// mid-session.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.backend, this.service});

  /// Test seams — production builds its own Firebase backend and service.
  final AuthBackend? backend;
  final SheetsService? service;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late AuthBackend _backend;
  late final SheetsService _service = widget.service ?? SheetsService();

  _GateState _state = _GateState.initializing;
  String _email = '';
  AppUser? _user;

  /// Set when a registered account is missing its department — the register
  /// screen reopens prefilled to collect just that.
  AppUser? _incomplete;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.backend != null) {
      _backend = widget.backend!;
    } else {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        // Placeholder firebase_options.dart (flutterfire configure not run
        // yet) or a broken config — say so instead of crashing.
        if (!mounted) return;
        setState(() {
          _state = _GateState.notConfigured;
          _error = e.toString();
        });
        return;
      }
      _backend = FirebaseAuthBackend();
    }

    final restored = _backend.currentEmail;
    if (restored == null || restored.isEmpty) {
      if (mounted) setState(() => _state = _GateState.loggedOut);
    } else {
      _checkProfile(restored);
    }
  }

  /// Firebase said yes — now the Users tab decides.
  Future<void> _checkProfile(String email) async {
    setState(() {
      _email = email;
      _state = _GateState.checking;
    });
    try {
      final user = await _service.fetchUserProfile(email);
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _incomplete = null;
          _state = _GateState.register;
        });
      } else if (!user.isActive) {
        setState(() => _state = _GateState.blocked);
      } else if (!user.hasDepartment) {
        // Registered before departments existed: they can't be shown a module
        // until they say which one is theirs.
        setState(() {
          _incomplete = user;
          _state = _GateState.register;
        });
      } else {
        _enter(user);
      }
    } on SheetsSubmissionException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GateState.checkFailed;
        _error = e.message;
      });
    }
  }

  void _enter(AppUser user) {
    if (!user.isActive) {
      // Registration succeeded, but the row starts inactive by design.
      setState(() => _state = _GateState.pendingApproval);
      return;
    }
    SheetsService.currentUserEmail = user.email;
    setState(() {
      _user = user;
      _state = _GateState.ready;
    });
  }

  Future<void> _signOut() async {
    SheetsService.currentUserEmail = null;
    await _backend.signOut();
    if (!mounted) return;
    setState(() {
      _user = null;
      _incomplete = null;
      _email = '';
      _state = _GateState.loggedOut;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.initializing:
      case _GateState.checking:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _GateState.notConfigured:
        return _MessageScreen(
          icon: Icons.build_circle_outlined,
          title: 'Firebase not configured',
          message:
              'Run `flutterfire configure` in the project folder, then '
              'rebuild the app.\n\n$_error',
        );
      case _GateState.loggedOut:
        return LoginScreen(
          backend: _backend,
          service: _service,
          onSignedIn: _checkProfile,
        );
      case _GateState.register:
        return RegisterScreen(
          email: _email,
          service: _service,
          existing: _incomplete,
          onRegistered: _enter,
          onSignOut: _signOut,
        );
      case _GateState.pendingApproval:
        return _MessageScreen(
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting for approval',
          message:
              "You're registered. An admin switches your account on in the "
              'Users sheet before you can log production — ask them to set '
              'your row to active, then sign in again.',
          actionLabel: 'SIGN OUT',
          onAction: _signOut,
        );
      case _GateState.blocked:
        return _MessageScreen(
          // Covers both a brand-new row awaiting approval and one that was
          // switched off, so the wording claims neither.
          icon: Icons.no_accounts_outlined,
          title: 'Account not active',
          message:
              'This account is registered but not active. An admin activates '
              'it in the Users sheet — contact them if you think this is a '
              'mistake.',
          actionLabel: 'SIGN OUT',
          onAction: _signOut,
        );
      case _GateState.checkFailed:
        return _MessageScreen(
          icon: Icons.cloud_off_rounded,
          title: 'Could not verify your account',
          message: _error,
          actionLabel: 'RETRY',
          onAction: () => _checkProfile(_email),
          secondaryLabel: 'SIGN OUT',
          onSecondary: _signOut,
        );
      case _GateState.ready:
        return AuthScope(
          user: _user!,
          signOut: _signOut,
          // Not const — see HicomOpsApp.home for why.
          // ignore: prefer_const_constructors
          child: HomeScreen(),
        );
    }
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
                if (secondaryLabel != null)
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
