import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hicom_ops/screens/auth_gate.dart';
import 'package:hicom_ops/screens/login_screen.dart';
import 'package:hicom_ops/services/auth_backend.dart';
import 'package:hicom_ops/services/sheets_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuthBackend implements AuthBackend {
  FakeAuthBackend({this.restoredEmail});

  String? restoredEmail;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  String? get currentEmail => restoredEmail;

  @override
  Future<String> signIn(String email, String password) async {
    signInCalls++;
    if (password == 'wrong') {
      throw const AuthFailure('Wrong email or password.');
    }
    return email;
  }

  @override
  Future<String> createAccount(String email, String password) async => email;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    restoredEmail = null;
  }
}

/// Users-tab backend stub: `profile` is what ?action=user returns.
SheetsService userService(Map<String, dynamic>? profile) {
  return SheetsService(
    client: MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response('{"status":"success"}', 200);
      }
      return http.Response(
        jsonEncode({'status': 'success', 'data': profile}),
        200,
      );
    }),
  );
}

void main() {
  tearDown(() => SheetsService.currentUserEmail = null);

  testWidgets('login: a non-company email never reaches Firebase', (
    tester,
  ) async {
    final backend = FakeAuthBackend();
    String? signedIn;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          backend: backend,
          onSignedIn: (email) => signedIn = email,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'ahmad@gmail.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Use your company email'), findsOneWidget);
    expect(backend.signInCalls, 0);
    expect(signedIn, isNull);
  });

  testWidgets('login: a company email signs in and hands back the email', (
    tester,
  ) async {
    final backend = FakeAuthBackend();
    String? signedIn;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          backend: backend,
          onSignedIn: (email) => signedIn = email,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Ahmad@hidsb.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.tap(find.text('SIGN IN'));
    // Plain pumps: on success the screen keeps its busy spinner (the gate
    // normally swaps it out), so pumpAndSettle would never settle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.signInCalls, 1);
    expect(signedIn, 'ahmad@hidsb.com', reason: 'email is normalised');
  });

  testWidgets('gate: a restored active session goes straight in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          backend: FakeAuthBackend(restoredEmail: 'ahmad@hidsb.com'),
          service: userService({
            'email': 'ahmad@hidsb.com',
            'name': 'Ahmad Ali',
            'employeeId': 'EMP-014',
            'status': 'active',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In: the home screen, with a sign-out button in the app bar and the
    // email attached to future saves.
    expect(find.text('Select production area'), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    expect(SheetsService.currentUserEmail, 'ahmad@hidsb.com');
  });

  testWidgets('gate: unregistered -> registration page -> in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          backend: FakeAuthBackend(restoredEmail: 'new@hidsb.com'),
          service: userService(null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Almost there'), findsOneWidget);
    expect(find.text('new@hidsb.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'New Person');
    await tester.enterText(find.byType(TextField).at(1), 'EMP-099');
    await tester.tap(find.text('REGISTER'));
    await tester.pumpAndSettle();

    expect(find.text('Select production area'), findsOneWidget);
    expect(SheetsService.currentUserEmail, 'new@hidsb.com');
  });

  testWidgets('gate: a deactivated account is blocked, sign-out works', (
    tester,
  ) async {
    final backend = FakeAuthBackend(restoredEmail: 'gone@hidsb.com');
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          backend: backend,
          service: userService({
            'email': 'gone@hidsb.com',
            'name': 'Left Company',
            'employeeId': 'EMP-001',
            'status': 'inactive',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account deactivated'), findsOneWidget);
    expect(find.text('Select production area'), findsNothing);
    expect(SheetsService.currentUserEmail, isNull);

    await tester.tap(find.text('SIGN OUT'));
    await tester.pumpAndSettle();
    expect(backend.signOutCalls, 1);
    expect(find.text('SIGN IN'), findsOneWidget); // back at the login screen
  });

  testWidgets('gate: signed out -> login screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(backend: FakeAuthBackend(), service: userService(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
  });
}
