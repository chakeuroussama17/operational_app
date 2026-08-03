import 'package:firebase_auth/firebase_auth.dart';

/// A sign-in failure with a message fit for the login screen.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The slice of Firebase Auth the app actually uses. A seam rather than
/// direct FirebaseAuth calls so login/gate widgets can be tested with a fake
/// (FirebaseAuth needs a configured app, which widget tests don't have).
abstract class AuthBackend {
  /// Signed-in email restored from the device session, or null.
  String? get currentEmail;

  /// Returns the signed-in email. Throws [AuthFailure] with a readable reason.
  Future<String> signIn(String email, String password);

  /// Creates the Firebase account and returns its email.
  Future<String> createAccount(String email, String password);

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Future<String> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user?.email ?? email;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<String> createAccount(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user?.email ?? email;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account for this email yet — use CREATE ACCOUNT first.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password.';
      case 'email-already-in-use':
        return 'An account already exists for this email — use SIGN IN.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'That is not a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts — wait a minute and try again.';
      case 'network-request-failed':
        return 'No connection. Check Wi-Fi / mobile data and try again.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
}
