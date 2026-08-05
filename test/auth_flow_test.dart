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
  int createAccountCalls = 0;

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
  Future<String> createAccount(String email, String password) async {
    createAccountCalls++;
    return email;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    restoredEmail = null;
  }
}

/// Users-tab backend stub: `profile` is what ?action=user returns; a
/// registration POST is recorded rather than actually stored, so the same
/// profile keeps coming back on the next GET unless the test wires its own
/// stateful client (see the sign-up test below).
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

/// Opens an [AuthGlassDropdown] and picks [option] — it renders its choices
/// in a popup route, so picking one is tap-to-open, then tap-the-item.
Future<void> _pickDropdown(WidgetTester tester, String option) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
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
          service: userService(null),
          onSignedIn: (email) => signedIn = email,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'ahmad@gmail.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.tap(find.text('LOG IN'));
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
          service: userService(null),
          onSignedIn: (email) => signedIn = email,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Ahmad@hidsb.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.tap(find.text('LOG IN'));
    // Plain pumps: on success the screen keeps its busy spinner (the gate
    // normally swaps it out), so pumpAndSettle would never settle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.signInCalls, 1);
    expect(signedIn, 'ahmad@hidsb.com', reason: 'email is normalised');
  });

  testWidgets('login: Sign up opens the combined create-account screen', (
    tester,
  ) async {
    final backend = FakeAuthBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          backend: backend,
          service: userService(null),
          onSignedIn: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Create an'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Employee ID'), findsOneWidget);
  });

  testWidgets(
    'sign-up: creates the Firebase account and the profile in one go',
    (tester) async {
      final backend = FakeAuthBackend();
      Map<String, dynamic>? registered;
      final service = SheetsService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            registered = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{"status":"success"}', 200);
          }
          return http.Response('{"status":"success","data":null}', 200);
        }),
      );
      String? signedUp;

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            backend: backend,
            service: service,
            onSignedIn: (email) => signedUp = email,
          ),
        ),
      );
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'New Person'); // Full Name
      await tester.enterText(fields.at(1), 'new@hidsb.com'); // Email
      await tester.enterText(fields.at(2), 'secret123'); // Password
      await tester.enterText(fields.at(3), 'secret123'); // Confirm
      await tester.enterText(fields.at(4), 'EMP-200'); // Employee ID
      await _pickDropdown(tester, 'Machining');

      await tester.ensureVisible(find.text('SIGN UP'));
      await tester.tap(find.text('SIGN UP'));
      // Plain pumps: on success the screen keeps its busy spinner (the gate
      // normally swaps it out), so pumpAndSettle would never settle here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(backend.createAccountCalls, 1);
      expect(registered!['op'], 'register');
      expect(registered!['email'], 'new@hidsb.com');
      expect(registered!['name'], 'New Person');
      expect(registered!['employeeId'], 'EMP-200');
      expect(registered!['department'], 'Machining');
      expect(signedUp, 'new@hidsb.com');
    },
  );

  testWidgets(
    'sign-up: mismatched passwords are refused before Firebase is called',
    (tester) async {
      final backend = FakeAuthBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            backend: backend,
            service: userService(null),
            onSignedIn: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'New Person');
      await tester.enterText(fields.at(1), 'new@hidsb.com');
      await tester.enterText(fields.at(2), 'secret123');
      await tester.enterText(fields.at(3), 'different');
      await tester.enterText(fields.at(4), 'EMP-200');

      await tester.ensureVisible(find.text('SIGN UP'));
      await tester.tap(find.text('SIGN UP'));
      await tester.pumpAndSettle();

      expect(find.textContaining("don't match"), findsOneWidget);
      expect(backend.createAccountCalls, 0);
    },
  );

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
            'department': 'Casting',
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

  testWidgets('a casting user is shown casting and nothing else', (
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
            'department': 'Casting',
            'status': 'active',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A department-scoped home names its module twice — the hero heading and
    // the tile — so what matters is that the OTHER two never appear.
    expect(find.text('Casting'), findsWidgets);
    expect(find.text('Secondary'), findsNothing);
    expect(find.text('Machining'), findsNothing);
  });

  testWidgets('the admin is shown every department', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          backend: FakeAuthBackend(restoredEmail: 'admin@hidsb.com'),
          service: userService({
            'email': 'admin@hidsb.com',
            'name': 'Boss',
            'employeeId': 'E0',
            'department': 'All',
            'status': 'active',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Casting'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Machining'), findsOneWidget);
  });

  testWidgets('an account with no department is sent back to finish', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          backend: FakeAuthBackend(restoredEmail: 'old@hidsb.com'),
          service: userService({
            'email': 'old@hidsb.com',
            'name': 'Old Hand',
            'employeeId': 'E9',
            'department': '',
            'status': 'active',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Prefilled with what the sheet already knows; only the department is
    // missing, and nothing is logged until it is chosen.
    expect(find.text('One more'), findsOneWidget);
    expect(find.text('Old Hand'), findsOneWidget);
    expect(find.text('Select production area'), findsNothing);
    expect(SheetsService.currentUserEmail, isNull);

    await _pickDropdown(tester, 'Secondary');
    await tester.ensureVisible(find.text('CONTINUE'));
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    // In, and confined to the department just chosen (named on both the hero
    // heading and the tile).
    expect(find.text('Secondary'), findsWidgets);
    expect(find.text('Casting'), findsNothing);
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

    expect(find.text('Almost'), findsOneWidget);
    expect(find.text('new@hidsb.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'New Person');
    await tester.enterText(find.byType(TextField).at(1), 'EMP-099');

    // A department is required — registering without one goes nowhere.
    await tester.ensureVisible(find.text('CONTINUE'));
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your department'), findsOneWidget);
    expect(find.text('Select production area'), findsNothing);

    await _pickDropdown(tester, 'Machining');
    await tester.ensureVisible(find.text('CONTINUE'));
    await tester.tap(find.text('CONTINUE'));
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
    expect(find.text('LOG IN'), findsOneWidget); // back at the login screen
  });

  testWidgets('gate: signed out -> login screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(backend: FakeAuthBackend(), service: userService(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
  });
}
