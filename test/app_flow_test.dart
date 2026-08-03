import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hicom_ops/services/sheets_service.dart';
import 'package:hicom_ops/config/theme_controller.dart';
import 'package:hicom_ops/main.dart';
import 'package:hicom_ops/screens/casting_entry_screen.dart';
import 'package:hicom_ops/screens/casting_home_screen.dart';
import 'package:hicom_ops/widgets/card_menu_button.dart';
import 'package:hicom_ops/screens/machining_entry_screen.dart';
import 'package:hicom_ops/screens/machining_home_screen.dart';
import 'package:hicom_ops/screens/secondary_home_screen.dart';
import 'package:hicom_ops/widgets/submit_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: inside widget tests all real HTTP is stubbed to return 400, so the
// casting screens (which fetch on load) are asserted in their error state.
void main() {
  testWidgets('home screen shows the three production area cards', (
    tester,
  ) async {
    await tester.pumpWidget(const HicomOpsApp());

    expect(find.text('Casting'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Machining'), findsOneWidget);
  });

  testWidgets('theme toggle cycles system -> light -> dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    themeController.value = ThemeMode.system;

    await tester.pumpWidget(const HicomOpsApp());
    expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.brightness_auto_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.light_mode_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(themeController.value, ThemeMode.dark);

    // Reset the shared global so later tests start from system.
    themeController.value = ThemeMode.system;
  });

  testWidgets('bottom nav switches between Log and Dashboard tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const HicomOpsApp());
    expect(find.text('Select production area'), findsOneWidget);

    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Select production area'), findsNothing);
    // Analytics fetch failed (stubbed 400) -> error body with Retry.
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(find.text('Select production area'), findsOneWidget);
  });

  testWidgets('area cards open the matching module', (tester) async {
    // Default test surface is short enough that the bottom nav bar leaves
    // the 3rd card too cramped to reliably hit-test; use a taller, more
    // tablet-realistic viewport (this app targets factory-floor tablets).
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HicomOpsApp());

    await tester.tap(find.text('Casting'));
    await tester.pumpAndSettle();
    expect(find.byType(CastingHomeScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Secondary'));
    await tester.pumpAndSettle();
    expect(find.byType(SecondaryHomeScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Machining'));
    await tester.pumpAndSettle();
    expect(find.byType(MachiningHomeScreen), findsOneWidget);
  });

  testWidgets('card 3-dots menu shows Edit/Delete and fires callbacks', (
    tester,
  ) async {
    var edited = false;
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CardMenuButton(
              onEdit: () => edited = true,
              onDelete: () => deleted = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(edited, isFalse);
  });

  testWidgets('casting home shows a retry error state when the fetch fails', (
    tester,
  ) async {
    await tester.pumpWidget(const HicomOpsApp());
    await tester.tap(find.text('Casting'));
    await tester.pumpAndSettle();

    // Dashboard fetch failed (stubbed 400) -> error body with Retry, and the
    // machine-selector heading is still present.
    expect(find.text('Select machine (DCM)'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('casting entry: partial-save guard and error snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CastingEntryScreen(dcm: '1212', part: '1', shift: 'Day'),
      ),
    );
    await tester.pumpAndSettle();

    // Row fetch failed -> warning banner, but the form is still editable.
    expect(
      find.textContaining('Saved data could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Plan'), findsOneWidget);
    // Day shift runs 8AM-6PM (not the old flat 10AM-8PM list).
    expect(find.text('Output — 8 AM'), findsOneWidget);
    expect(find.text('Output — 6 PM'), findsOneWidget);
    expect(find.text('LOR'), findsNWidgets(6));

    // Submitting with no values entered is a no-op with a hint.
    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();
    expect(find.text('Nothing new to save yet.'), findsOneWidget);

    // With a value entered, submit posts and surfaces the server failure.
    await tester.enterText(find.byType(TextFormField).first, '300');
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Server error (400)'), findsWidgets);

    // Let snackbar timers elapse so the test ends cleanly.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('machining home shows a retry error state when the fetch fails', (
    tester,
  ) async {
    // See note in 'area cards open the matching module' re: viewport size.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HicomOpsApp());
    await tester.tap(find.text('Machining'));
    await tester.pumpAndSettle();

    // Dashboard fetch failed (stubbed 400) -> error body with Retry, and
    // the customer-selector heading is still present.
    expect(find.text('Select customer'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('machining entry: partial-save guard and error snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MachiningEntryScreen(
          customer: 'Mazda',
          part: '1',
          line: 'Line 1',
          shift: 'Day',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Row fetch failed -> warning banner, but the form is still editable.
    expect(
      find.textContaining('Saved data could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Plan'), findsOneWidget);
    // Day shift slots run 8 AM - 6 PM, each with its own rejection line
    // beneath it, and one auto-calculated summary at the bottom.
    expect(find.text('Output — 8 AM'), findsOneWidget);
    expect(find.text('Output — 6 PM'), findsOneWidget);
    expect(find.text('LOR'), findsNWidgets(6));
    expect(find.text('Select type'), findsNWidgets(6));
    expect(find.text('Another defect this hour'), findsNWidgets(6));
    expect(find.text('Rejection summary'), findsOneWidget);
    expect(find.text('No rejections logged this shift.'), findsOneWidget);

    // Submitting with no values entered is a no-op with a hint.
    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();
    expect(find.text('Nothing new to save yet.'), findsOneWidget);

    // With a value entered, submit posts and surfaces the server failure.
    await tester.enterText(find.byType(TextFormField).first, '300');
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Server error (400)'), findsWidgets);

    // Let snackbar timers elapse so the test ends cleanly.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('machining entry: an hour can carry more than one defect', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MachiningEntryScreen(
          customer: 'Mazda',
          part: '2244',
          line: 'FY2',
          shift: 'Day',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every hour starts with exactly one rejection line.
    expect(find.text('Select type'), findsNWidgets(6));

    await tester.dragUntilVisible(
      find.text('Another defect this hour').first,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Another defect this hour').first);
    await tester.pumpAndSettle();
    expect(find.text('Select type'), findsNWidgets(7));

    // The extra line can be dropped again (a lone line has no x).
    final remove = find.byIcon(Icons.close);
    expect(
      remove,
      findsNWidgets(2),
      reason: 'both lines of that hour get an x',
    );
    await tester.ensureVisible(remove.first);
    await tester.tap(remove.first);
    await tester.pumpAndSettle();
    expect(find.text('Select type'), findsNWidgets(6));

    // A quantity with no defect type chosen is not a rejection, so it stays
    // out of the summary and there is still nothing to save.
    // Fields run Plan, Output 8AM, qty 8AM, Output 10AM, qty 10AM, ...
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.pumpAndSettle();
    expect(find.text('No rejections logged this shift.'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();
    expect(find.text('Nothing new to save yet.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('machining entry: saved hours lock, rejections stay visible', (
    tester,
  ) async {
    // A stateful stand-in for the backend: Plan 300 and 8 AM = 150 are saved,
    // with 5 POROSITY logged against that hour. Posted lines are merged by
    // (hour, type) the way the real reconcile does.
    var storedRejections = <dynamic>[
      {'code': '064', 'type': 'POROSITY', 'qty': '5', 'slot': '8AM'},
    ];
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        if (data['Rejections'] != null) {
          for (final raw
              in jsonDecode(data['Rejections'] as String) as List<dynamic>) {
            final entry = raw as Map<String, dynamic>;
            final match = storedRejections.cast<Map<String, dynamic>>().where(
              (r) => r['slot'] == entry['slot'] && r['type'] == entry['type'],
            );
            if (match.isEmpty) {
              storedRejections.add(entry);
            } else {
              match.first['qty'] = entry['qty'];
            }
          }
        }
        return http.Response('{"status":"success"}', 200);
      }
      if (request.url.queryParameters['action'] == 'rejectiontypes') {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': [
              {'code': '064', 'type': 'POROSITY'},
              {'code': '037', 'type': 'FLASHES'},
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'Customer': 'Mazda',
            'PartNo': '2244',
            'Line': 'FY2',
            'Plan': 400,
            'Output_8AM': 150,
            'Output_LOR8AM': 0.375,
            'LogMeta': '{"8AM":{"by":"Ahmad Ali","at":"08:07"}}',
            'Rejections': storedRejections,
          },
        }),
        200,
      );
    });

    SheetsService.clearMasterCaches();
    await tester.pumpWidget(
      MaterialApp(
        home: MachiningEntryScreen(
          customer: 'Mazda',
          part: '2244',
          line: 'FY2',
          shift: 'Day',
          service: SheetsService(client: mock),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Plan and the saved hour are both read-only boxes, and the hour carries
    // who logged it. The saved defect sits under its own hour.
    expect(find.text('Added by Ahmad Ali at 08:07'), findsOneWidget);
    expect(find.text('064 · POROSITY'), findsNWidgets(2)); // hour + summary
    // Plan and 8 AM's output are locked boxes, not fields: 5 editable outputs
    // + 6 new-defect qty boxes + the saved defect's own qty box.
    expect(find.byType(TextFormField), findsNWidgets(12));
    // LOR is cumulative over Plan: 150 of 400.
    expect(find.text('37.5%'), findsOneWidget);
    expect(find.text('250'), findsOneWidget, reason: 'left to plan');

    // Correcting the saved 5 down to 3 hands 2 pieces back to the 8 AM output.
    await tester.enterText(find.byType(TextFormField).at(0), '3');
    await tester.pumpAndSettle();
    expect(
      find.text('152'),
      findsNWidgets(2),
      reason: "the hour's box and the shift total both move",
    );
    expect(find.text('38%'), findsOneWidget, reason: '152 of 400');
    expect(find.text('248'), findsOneWidget, reason: 'left to plan follows');
    // The qty box itself, plus the summary's line and total.
    expect(find.text('3'), findsNWidgets(3));

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();

    // The correction posted with its hour attached.
    expect(find.text('064 · POROSITY'), findsNWidgets(2));
    expect(
      (storedRejections.first as Map)['qty'],
      '3',
      reason: 'the corrected quantity reached the sheet',
    );
    expect((storedRejections.first as Map)['slot'], '8AM');

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('machining entry: an untouched saved defect is not re-posted', (
    tester,
  ) async {
    Map<String, dynamic>? posted;
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        posted =
            (jsonDecode(request.body) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        return http.Response('{"status":"success"}', 200);
      }
      if (request.url.queryParameters['action'] == 'rejectiontypes') {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': [
              {'code': '064', 'type': 'POROSITY'},
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'Plan': 400,
            'Output_8AM': 150,
            'Rejections': [
              {'code': '064', 'type': 'POROSITY', 'qty': '5', 'slot': '8AM'},
            ],
          },
        }),
        200,
      );
    });

    SheetsService.clearMasterCaches();
    await tester.pumpWidget(
      MaterialApp(
        home: MachiningEntryScreen(
          customer: 'Mazda',
          part: '2244',
          line: 'FY2',
          shift: 'Day',
          service: SheetsService(client: mock),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Log a fresh 10 AM output without touching the saved defect. Plan and the
    // 8 AM output are locked boxes, so the fields run: 8 AM's saved-defect
    // qty, 8 AM's new-defect qty, then the 10 AM output.
    await tester.enterText(find.byType(TextFormField).at(2), '120');
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();

    expect(posted!['Output_10AM'], '120');
    expect(
      posted!.containsKey('Rejections'),
      isFalse,
      reason: 'nothing about the defect list changed, so it is left alone',
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('number fields ignore non-numeric input', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MachiningEntryScreen(
          customer: 'Mazda',
          part: '1',
          line: 'Line 1',
          shift: 'Day',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Plan is the first number field on the machining entry form.
    final planField = find.byType(TextFormField).first;
    await tester.enterText(planField, 'abc123');

    expect(find.text('123'), findsOneWidget); // letters were filtered out
  });
}
