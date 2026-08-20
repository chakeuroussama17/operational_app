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
import 'package:hicom_ops/config/constants.dart';
import 'package:hicom_ops/widgets/manage_dialogs.dart';
import 'package:hicom_ops/models/machining_models.dart';
import 'package:hicom_ops/models/part_code.dart';
import 'package:hicom_ops/models/raw_table.dart';
import 'package:hicom_ops/models/sheet_export.dart';
import 'package:hicom_ops/screens/tables_screen.dart';
import 'package:hicom_ops/screens/machining_entry_screen.dart';
import 'package:hicom_ops/screens/machining_operations_screen.dart';
import 'package:hicom_ops/screens/secondary_home_screen.dart';
import 'package:hicom_ops/widgets/submit_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: inside widget tests all real HTTP is stubbed to return 400, so the
// casting screens (which fetch on load) are asserted in their error state.
void main() {
  testWidgets('home screen shows the three production area cards', (
    tester,
  ) async {
    // The home page leads with a hero badge and a KPI strip now, so the
    // module tiles need a taller surface than the 600px default to all be
    // laid out at once.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HicomOpsApp());
    await tester.pumpAndSettle();

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
    expect(find.byType(MachiningOperationsScreen), findsOneWidget);
    // Operation comes first now: machining or assembly, then the customer.
    expect(find.text('Assembly'), findsOneWidget);
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
    // See the note in 'home screen shows the three production area cards'.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const HicomOpsApp());
    await tester.pumpAndSettle();
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
    // Day shift runs 10AM-6PM — five checkpoints, no 8AM.
    expect(find.text('Actual — 10 AM'), findsOneWidget);
    expect(find.text('Actual — 6 PM'), findsOneWidget);
    expect(find.text('Actual — 8 AM'), findsNothing);
    expect(find.text('LOR'), findsNWidgets(5));

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

    // The module opens on the operation picker, which makes no network call
    // of its own — the customer fetch is one level down.
    expect(find.text('Select operation'), findsOneWidget);
    await tester.tap(find.text('Assembly'));
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
          operation: machiningOperation,
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
    // Day slots run 10 AM - 6 PM, each with its own rejection line beneath
    // it, and one overall summary at the bottom.
    expect(find.text('Actual — 10 AM'), findsOneWidget);
    expect(find.text('Actual — 6 PM'), findsOneWidget);
    expect(find.text('LOR'), findsNWidgets(5));
    expect(find.text('Select type'), findsNWidgets(5));
    expect(find.text('Another defect this hour'), findsNWidgets(5));
    expect(find.text('Overall summary'), findsOneWidget);
    expect(find.text('Total good parts'), findsOneWidget);
    // Nothing logged yet, so there is no per-defect breakdown to show.
    expect(find.text('Rejection summary'), findsNothing);

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
          operation: machiningOperation,
          shift: 'Day',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every hour starts with exactly one rejection line — five on Day.
    expect(find.text('Select type'), findsNWidgets(5));

    await tester.dragUntilVisible(
      find.text('Another defect this hour').first,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Another defect this hour').first);
    await tester.pumpAndSettle();
    expect(find.text('Select type'), findsNWidgets(6));

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
    expect(find.text('Select type'), findsNWidgets(5));

    // A quantity with no defect type chosen is not a rejection, so it stays
    // out of the summary and there is still nothing to save.
    // Fields run Plan, Actual 10AM, qty 10AM, Actual 12PM, qty 12PM, ...
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.pumpAndSettle();
    expect(find.text('Rejection summary'), findsNothing);

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
      {'code': '064', 'type': 'POROSITY', 'qty': '5', 'slot': '10AM'},
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
            'Operation': 'machining',
            'Plan': 400,
            'Actual_10AM': 150,
            'LOR_10AM': 0.375,
            'LogMeta': '{"10AM":{"by":"Ahmad Ali","at":"08:07"}}',
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
          operation: machiningOperation,
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
    // Plan and 10 AM's actual are locked boxes, not fields. Each hour now
    // contributes a downtime box too: 4 editable actuals + 5 new-defect qty
    // boxes + 5 downtime boxes + the saved defect's own qty box.
    expect(find.byType(TextFormField), findsNWidgets(15));
    // LOR is cumulative over Plan: 150 of 400.
    expect(find.text('37.5%'), findsOneWidget);
    // Actual counts everything made, so good = 150 - 5.
    expect(find.text('150 / 400'), findsOneWidget);
    expect(find.text('145'), findsOneWidget, reason: 'good parts');

    // Correcting the saved 5 down to 3 must NOT move the actual figure —
    // actual is everything the hour made, and a defect correction only
    // changes how that total splits between good and scrap.
    await tester.enterText(find.byType(TextFormField).at(0), '3');
    await tester.pumpAndSettle();
    expect(
      find.text('150 / 400'),
      findsOneWidget,
      reason: 'the hour produced 150 either way',
    );
    expect(find.text('37.5%'), findsOneWidget, reason: 'LOR follows actual');
    expect(find.text('147'), findsOneWidget, reason: 'good parts: 150 - 3');
    // The qty box, the summary's own line, and the rejected-parts total.
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
    expect((storedRejections.first as Map)['slot'], '10AM');

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
            'Actual_10AM': 150,
            'Rejections': [
              {'code': '064', 'type': 'POROSITY', 'qty': '5', 'slot': '10AM'},
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
          operation: machiningOperation,
          shift: 'Day',
          service: SheetsService(client: mock),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Log a fresh 12 PM actual without touching the saved defect. Plan and the
    // 10 AM actual are locked boxes, so the fields run: 10 AM's saved-defect
    // qty, its new-defect qty, its downtime, then the 12 PM actual.
    await tester.enterText(find.byType(TextFormField).at(3), '120');
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();

    expect(posted!['Actual_12PM'], '120');
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
          operation: machiningOperation,
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

  group('part picker is split by operation', () {
    // Real entries from the plant's Parts master.
    const master = [
      PartCode(
        code: '2244',
        barcode: '2244-MAR-M',
        name: '2244-MAR-NO2-BRKT-ENGINE-LH-MACH',
      ),
      PartCode(
        code: '2215',
        barcode: '2215-MAZ-A',
        name: '2215-MAZ-PIPE-CONNECTOR-ASSY',
      ),
      // Name says ASSY in the MIDDLE and MACH at the end — the END is what
      // decides, or every "…-CASE-ASSY-CHAIN-MACH" would land in assembly.
      PartCode(
        code: '2266',
        barcode: '2266-HON-M',
        name: '2266-HON-CASE-ASSY-CHAIN-MACH',
      ),
      // Named for the step, not the operation; only the barcode classifies it.
      PartCode(
        code: '2230',
        barcode: '2230-PR2-A',
        name: '2230-PR2-BRKT-OIL-FILTER-LEAKTEST',
      ),
      PartCode(code: '9999', barcode: null, name: null),
    ];

    test('machining takes the MACH names', () {
      final codes = partCodesForOperation(master, machiningOperation);
      expect(codes.map((c) => c.code), ['2244', '2266']);
    });

    test('assembly takes the ASSY names', () {
      final codes = partCodesForOperation(master, assemblyOperation);
      expect(codes.map((c) => c.code), ['2215', '2230']);
    });

    test('a part with nothing to classify it lands in neither list', () {
      final everything = [
        ...partCodesForOperation(master, machiningOperation),
        ...partCodesForOperation(master, assemblyOperation),
      ];
      expect(everything.map((c) => c.code), isNot(contains('9999')));
    });
  });

  testWidgets('part picker: a code missing from the list can be typed in', (
    tester,
  ) async {
    PartWithMoInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await promptPartCode(
                  context,
                  title: 'Add Part',
                  moduleLabel: 'Machining',
                  codes: const [
                    PartCode(
                      code: '2244',
                      barcode: '2244-MAR-M',
                      name: '2244-MAR-NO2-BRKT-ENGINE-LH-MACH',
                    ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The list starts shut; tapping the picker row opens it.
    await tester.tap(find.text('Choose part code'));
    await tester.pumpAndSettle();

    // A code the Parts master doesn't have.
    await tester.enterText(find.byType(TextField).first, '2299');
    await tester.pumpAndSettle();
    expect(find.text('Use "2299"'), findsOneWidget);

    await tester.tap(find.text('Use "2299"'));
    await tester.pumpAndSettle();

    // Closes like a normal pick, and says the code is off-list.
    expect(find.text('2299'), findsOneWidget);
    expect(find.text('Typed in — not on the parts list'), findsOneWidget);

    await tester.tap(find.text('SAVE 2299'));
    await tester.pumpAndSettle();
    expect(result?.name, '2299');
  });

  testWidgets('part picker: an existing code is picked, not re-typed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => promptPartCode(
                context,
                title: 'Add Part',
                moduleLabel: 'Machining',
                codes: const [
                  PartCode(code: '2244', barcode: '2244-MAR-M', name: 'BRKT'),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose part code'));
    await tester.pumpAndSettle();

    // Typing a code that IS on the list must not offer to duplicate it.
    await tester.enterText(find.byType(TextField).first, '2244');
    await tester.pumpAndSettle();
    expect(find.text('Use "2244"'), findsNothing);
  });

  group('casting machine picker', () {
    Future<String?> open(
      WidgetTester tester, {
      String? initialValue,
      Set<String> taken = const {},
    }) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await promptFromList(
                    context,
                    title: 'Add machine',
                    options: castingMachines,
                    initialValue: initialValue,
                    taken: taken,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('picking a machine returns it and closes', (tester) async {
      await open(tester);
      expect(find.text('DCM08'), findsOneWidget);

      await tester.tap(find.text('DCM08'));
      await tester.pumpAndSettle();
      // Dialog is gone; the button that opened it is showing again.
      expect(find.text('DCM08'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('a machine already on the grid cannot be added twice', (
      tester,
    ) async {
      await open(tester, taken: {'DCM08'});

      expect(find.text('Already added'), findsOneWidget);
      await tester.tap(find.text('DCM08'));
      await tester.pumpAndSettle();
      // Still open — the tap did nothing.
      expect(find.text('DCM08'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
    });

    testWidgets('a legacy name is listed so it can be moved onto a real one', (
      tester,
    ) async {
      // The seeded placeholders (1212, 3131...) predate this list; renaming is
      // how they become real machines, so the old name needs a row.
      await open(tester, initialValue: '1212', taken: {'1212'});

      expect(find.text('1212'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('DCM08'), findsOneWidget);
    });

    test('the machine list matches the plant, gaps included', () {
      expect(castingMachines, hasLength(21));
      expect(castingMachines.first, 'DCM08');
      expect(castingMachines.last, 'WELD');
      // Machines that do not exist must never be offered.
      for (final missing in ['DCM09', 'DCM10', 'DCM13', 'DCM14', 'DCM16', 'DCM22']) {
        expect(castingMachines, isNot(contains(missing)));
      }
      expect(castingMachines.toSet(), hasLength(castingMachines.length));
    });
  });

  group('secondary station picker', () {
    testWidgets('stations are picked from the list, duplicates blocked', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => promptFromList(
                  context,
                  title: 'Add station',
                  options: secondaryStations,
                  taken: const {'CURING'},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('CURING'), findsOneWidget);
      expect(find.text('Already added'), findsOneWidget);

      // The taken one does nothing; a free one closes the dialog.
      await tester.tap(find.text('CURING'));
      await tester.pumpAndSettle();
      expect(find.text('CANCEL'), findsOneWidget);

      await tester.tap(find.text('FETTLING'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(find.text('CANCEL'), findsNothing);
    });

    test('the station list matches the plant', () {
      expect(secondaryStations, hasLength(18));
      expect(secondaryStations.toSet(), hasLength(secondaryStations.length));
      // Numbered runs are complete and have no gaps, unlike the DCMs.
      for (var i = 1; i <= 9; i++) {
        expect(secondaryStations, contains('TRIM0$i'));
      }
      for (var i = 1; i <= 4; i++) {
        expect(secondaryStations, contains('ROBO0$i'));
      }
      // Full names, not truncations of longer ones.
      expect(secondaryStations, containsAll(['SHOTB-BT', 'SHOTB-GR']));
      expect(secondaryStations, containsAll(['CURING', 'FETTLING', 'TUMBLING']));
      // The old seeded placeholders are not real stations.
      expect(secondaryStations, isNot(contains('ST1')));
    });
  });

  testWidgets('machining entry: downtime posts per hour and totals up', (
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
        return http.Response('{"status":"success","data":[]}', 200);
      }
      return http.Response('{"status":"success","data":null}', 200);
    });

    SheetsService.clearMasterCaches();
    await tester.pumpWidget(
      MaterialApp(
        home: MachiningEntryScreen(
          customer: 'Mazda',
          part: '2244',
          operation: machiningOperation,
          shift: 'Day',
          service: SheetsService(client: mock),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every hour carries its own downtime box, under that hour's defects.
    expect(find.text('Downtime this hour'), findsNWidgets(5));

    // Nothing saved yet, so fields run: Plan, then per hour
    // actual / defect qty / downtime.
    await tester.enterText(find.byType(TextFormField).at(1), '40'); // 10AM
    await tester.enterText(find.byType(TextFormField).at(3), '20'); // 10AM min
    await tester.enterText(find.byType(TextFormField).at(6), '10'); // 12PM min
    await tester.pumpAndSettle();

    // The summary adds the minutes up across the shift.
    expect(find.text('30 min'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();

    expect(posted!['Actual_10AM'], '40');
    expect(posted!['Downtime_10AM'], '20');
    expect(posted!['Downtime_12PM'], '10');
    expect(
      posted!.containsKey('Downtime_2PM'),
      isFalse,
      reason: 'an hour nobody typed into is not claimed as zero downtime',
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  group('sheet tables', () {
    test('a department only sees its own tabs', () {
      expect(
        rawTabsFor(['casting']).map((t) => t.name),
        ['Casting_Day', 'Casting_Night'],
      );
      expect(
        rawTabsFor(['machining']).map((t) => t.name),
        ['Machining_Day', 'Machining_Night', 'Machining_Rejections'],
      );
      // Admin (every department) and widget tests (empty) get all of them.
      expect(rawTabsFor(const []).length, 7);
      expect(rawTabsFor(['casting', 'secondary', 'machining']).length, 7);
    });

    test('a capped table says so, an uncapped one does not', () {
      const short = RawTable(tab: 'Casting_Day', cols: ['Date'],
          rows: [['2026-08-17']], total: 1);
      expect(short.isCapped, isFalse);
      const capped = RawTable(tab: 'Machining_Day', cols: ['Date'],
          rows: [['2026-08-17']], total: 4812);
      expect(capped.isCapped, isTrue);
    });

    testWidgets('renders the sheet verbatim and searches every column', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late Uri requested;
      final mock = MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"status":"success","data":{"tab":"Casting_Day",'
          '"cols":["Date","DCM","PartNo","Plan"],'
          '"rows":[["2026-08-17","DCM21","2244","300"],'
          '["2026-08-16","DCM24","2215",""]],'
          '"total":2}}',
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TablesScreen(service: SheetsService(client: mock)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(requested.queryParameters['action'], 'rawtab');
      expect(requested.queryParameters['name'], 'Casting_Day');

      // Header and both rows, exactly as the sheet gave them.
      expect(find.text('DCM'), findsOneWidget);
      expect(find.text('DCM21'), findsOneWidget);
      expect(find.text('2244'), findsOneWidget);
      expect(find.text('2 rows · 4 columns'), findsOneWidget);
      // A blank cell reads as an em dash rather than as nothing at all.
      expect(find.text('—'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'DCM24');
      await tester.pumpAndSettle();
      expect(find.text('DCM21'), findsNothing);
      // The search field holds the typed text too, so the surviving row's
      // cell is one of two matches rather than the only one.
      expect(find.text('DCM24'), findsWidgets);
      expect(find.text('1 of 2 rows match'), findsOneWidget);
    });
  });

  group('sheet download', () {
    test('today is one day; month runs 1st to last, February included', () {
      final t = DateWindow.forRange(
          ExportRange.today, DateTime(2026, 8, 17, 14, 30));
      expect(t.isSingleDay, isTrue);
      expect(t.label, '2026-08-17');

      final m = DateWindow.forRange(ExportRange.month, DateTime(2026, 8, 17));
      expect(m.from, DateTime(2026, 8, 1));
      expect(m.to, DateTime(2026, 8, 31));

      // Day 0 of the next month is the trap: a naive +30 lands in March.
      final feb = DateWindow.forRange(ExportRange.month, DateTime(2026, 2, 9));
      expect(feb.to, DateTime(2026, 2, 28));
      final leap = DateWindow.forRange(ExportRange.month, DateTime(2028, 2, 9));
      expect(leap.to, DateTime(2028, 2, 29));

      // A December window must not roll the year.
      final dec = DateWindow.forRange(ExportRange.month, DateTime(2026, 12, 5));
      expect(dec.to, DateTime(2026, 12, 31));
    });

    test('both ends of the window are inclusive', () {
      final w = DateWindow(DateTime(2026, 8, 10), DateTime(2026, 8, 12));
      expect(w.contains(DateTime(2026, 8, 10)), isTrue);
      expect(w.contains(DateTime(2026, 8, 12, 23, 59)), isTrue);
      expect(w.contains(DateTime(2026, 8, 9)), isFalse);
      expect(w.contains(DateTime(2026, 8, 13)), isFalse);
    });

    test('sheet dates parse in either format the tabs use', () {
      expect(parseSheetDate('2026-08-17'), DateTime(2026, 8, 17));
      expect(parseSheetDate('2026-08-17 14:38:48'), DateTime(2026, 8, 17));
      // Day-first, as the plant writes them.
      expect(parseSheetDate('17/08/2026'), DateTime(2026, 8, 17));
      expect(parseSheetDate(''), isNull);
      expect(parseSheetDate('not a date'), isNull);
    });

    test('rows outside the window, and undated rows, are left out', () {
      const table = RawTable(
        tab: 'Machining_Day',
        cols: ['Date', 'Customer', 'PartNo'],
        rows: [
          ['2026-08-17', 'Mazda', '2244'],
          ['2026-08-11', 'Proton', '2215'],
          ['', 'Toyota', '2214'],
        ],
        total: 3,
      );
      final w = DateWindow(DateTime(2026, 8, 15), DateTime(2026, 8, 18));
      final rows = rowsInWindow(table, w);
      expect(rows.length, 1);
      expect(rows.first[1], 'Mazda');

      // A download labelled for a month must not smuggle an undated row in.
      final wide = DateWindow(DateTime(2020, 1, 1), DateTime(2030, 1, 1));
      expect(rowsInWindow(table, wide).length, 2);
    });

    test('a value containing a comma survives the round trip', () {
      final csv = toCsv(
        ['PartName', 'Qty'],
        [
          ['BRKT, ENGINE LH', '5'],
          ['SAYS "NG"', '3'],
        ],
      );
      final lines = csv.trim().split('\n');
      expect(lines[0], 'PartName,Qty');
      // Quoted, so it stays ONE column rather than becoming two.
      expect(lines[1], '"BRKT, ENGINE LH",5');
      // Embedded quotes are doubled, per RFC 4180.
      expect(lines[2], '"SAYS ""NG""",3');
    });

    test('a short row is padded, never truncating the header', () {
      final csv = toCsv(['A', 'B', 'C'], [['1']]);
      expect(csv.trim().split('\n')[1], '1,,');
    });

    test('the file is named for the tab and the window', () {
      expect(
        exportFileName('Machining_Day',
            DateWindow(DateTime(2026, 8, 17), DateTime(2026, 8, 17))),
        'Machining_Day_2026-08-17.csv',
      );
      expect(
        exportFileName('Casting_Night',
            DateWindow(DateTime(2026, 8, 1), DateTime(2026, 8, 31))),
        'Casting_Night_2026-08-01_to_2026-08-31.csv',
      );
    });
  });
}
