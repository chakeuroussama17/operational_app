// PLACEHOLDER — run `flutterfire configure` in the project folder and it
// overwrites this file with the real project config. Keeping the same shape
// lets the app compile and the tests run before Firebase is wired; at runtime
// the auth gate catches the throw below and shows a "not configured" screen
// instead of crashing.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet — run `flutterfire configure`.',
    );
  }
}
