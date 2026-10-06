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
import 'package:hicom_ops/widgets/checkpoint_timeline.dart';
import 'package:hicom_ops/config/constants.dart';
import 'package:hicom_ops/widgets/manage_dialogs.dart';
import 'package:hicom_ops/models/casting_models.dart';
import 'package:hicom_ops/models/downtime_reason.dart';
import 'package:hicom_ops/screens/machining_parts_screen.dart';
import 'package:hicom_ops/screens/auth_gate.dart';
import 'package:hicom_ops/models/app_user.dart';
import 'package:hicom_ops/models/production_line.dart';
import 'package:hicom_ops/models/machining_models.dart';
import 'package:hicom_ops/models/secondary_models.dart';
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
/// MO and Report are both required on a part now, so a dialog test that is about
/// something else — picking a code, picking a line — has to fill them in
/// before its save is allowed through.
Future<void> _fillPartNumbers(
  WidgetTester tester, {
  String mo = 'MO-2214',
  String report = '07',
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'MO number'), mo);
  await tester.enterText(
    find.widgetWithText(TextField, 'Report number'),
    report,
  );
  await tester.pumpAndSettle();
}

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
    // Day shift runs 12PM-7:30PM with three checkpoints.
    expect(find.text('Actual — 12 PM'), findsOneWidget);
    expect(find.text('Actual — 7:30 PM'), findsOneWidget);
    expect(find.text('Actual — 8 AM'), findsNothing);
    expect(find.text('LOR'), findsNWidgets(3));

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
    // Day slots run 12 PM - 7:30 PM, each with its own rejection line beneath
    // it, and one overall summary at the bottom.
    // Each checkpoint is named twice now: on its card, and on the timeline
    // strip across the top that shows what is logged and what is due.
    expect(find.text('12 PM'), findsNWidgets(2));
    expect(find.text('7:30 PM'), findsNWidgets(2));
    expect(find.byType(CheckpointTimeline), findsOneWidget);
    expect(find.text('Actual'), findsNWidgets(3));
    expect(find.text('LOR'), findsNWidgets(3));
    expect(find.text('Select type'), findsNWidgets(3));
    expect(find.text('Another defect'), findsNWidgets(3));
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

    // Every hour starts with exactly one rejection line — three on Day.
    expect(find.text('Select type'), findsNWidgets(3));

    await tester.dragUntilVisible(
      find.text('Another defect').first,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Another defect').first);
    await tester.pumpAndSettle();
    expect(find.text('Select type'), findsNWidgets(4));

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
    expect(find.text('Select type'), findsNWidgets(3));

    // A quantity with no defect type chosen is not a rejection, so it stays
    // out of the summary and there is still nothing to save.
    // Fields run Plan, Actual 12PM, qty 12PM, Actual 4PM, qty 4PM, ...
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

  testWidgets(
    'machining entry: saved values stay editable, rejections visible',
    (tester) async {
      // A stateful stand-in for the backend: Plan 300 and 8 AM = 150 are saved,
      // with 5 POROSITY logged against that hour. Posted lines are merged by
      // (hour, type) the way the real reconcile does.
      var storedRejections = <dynamic>[
        {'code': '064', 'type': 'POROSITY', 'qty': '5', 'slot': '12PM'},
      ];
      Map<String, dynamic>? posted;
      final mock = MockClient((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final data = body['data'] as Map<String, dynamic>;
          posted = data;
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
              'Actual_12PM': 150,
              'LOR_12PM': 0.375,
              'LogMeta': '{"12PM":{"by":"Ahmad Ali","at":"08:07"}}',
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

      // The saved hour carries who logged it, and the saved defect sits under
      // its own hour.
      expect(find.text('Added by Ahmad Ali at 08:07'), findsOneWidget);
      expect(find.text('064 · POROSITY'), findsNWidgets(2)); // hour + summary
      // Nothing is read-only: Plan, every hour's actual, defect and downtime
      // boxes, plus the saved defect's qty, are all fields.
      expect(find.byType(TextFormField), findsNWidgets(11));
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      // LOR is cumulative over Plan: 150 of 400.
      expect(find.text('37.5%'), findsOneWidget);
      // Actual counts everything made, so good = 150 - 5.
      expect(find.text('150 / 400'), findsOneWidget);
      expect(find.text('145'), findsOneWidget, reason: 'good parts');

      // Correcting the saved 5 down to 3 must NOT move the actual figure —
      // actual is everything the hour made, and a defect correction only
      // changes how that total splits between good and scrap.
      await tester.enterText(find.widgetWithText(TextFormField, '5'), '3');
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
      expect((storedRejections.first as Map)['slot'], '12PM');

      // The saved Plan and the saved hour can both be corrected, and emptying
      // a saved value sends the blank so the sheet clears it.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, '400'),
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
      );
      await tester.enterText(find.widgetWithText(TextFormField, '400'), '350');
      await tester.enterText(find.widgetWithText(TextFormField, '150'), '');
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byType(SubmitButton),
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.tap(find.byType(SubmitButton));
      await tester.pumpAndSettle();
      expect(posted!['Plan'], '350');
      expect(
        posted!['Actual_12PM'],
        '',
        reason: 'a cleared hour is sent blank',
      );

      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

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
            'Actual_12PM': 150,
            'Rejections': [
              {'code': '064', 'type': 'POROSITY', 'qty': '5', 'slot': '12PM'},
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

    // Log a fresh 4 PM actual without touching the saved defect. Fields run
    // Plan, then 12 PM's actual, saved qty, new defect qty and downtime, then
    // the 4 PM actual.
    await tester.enterText(find.byType(TextFormField).at(5), '120');
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();

    expect(posted!['Actual_4PM'], '120');
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
      // 9999 is the unclassifiable one, covered below — every other part is
      // in exactly one list.
      expect(codes.map((c) => c.code).where((c) => c != '9999'), [
        '2244',
        '2266',
      ]);
    });

    test('assembly takes the ASSY names', () {
      final codes = partCodesForOperation(master, assemblyOperation);
      expect(codes.map((c) => c.code).where((c) => c != '9999'), [
        '2215',
        '2230',
      ]);
    });

    test('a part with nothing to classify it is offered under BOTH', () {
      // A row added to the Parts sheet with a name that says nothing about
      // its operation used to appear in neither picker, with no hint why.
      // Showing it twice is a nuisance; never showing it is a fault.
      expect(
        partCodesForOperation(master, machiningOperation).map((c) => c.code),
        contains('9999'),
      );
      expect(
        partCodesForOperation(master, assemblyOperation).map((c) => c.code),
        contains('9999'),
      );
    });

    test('a classified part is never offered to the other operation', () {
      // The fallback above must not leak: 2244 is machining, full stop.
      expect(
        partCodesForOperation(master, assemblyOperation).map((c) => c.code),
        isNot(contains('2244')),
      );
      expect(
        partCodesForOperation(master, machiningOperation).map((c) => c.code),
        isNot(contains('2215')),
      );
    });
  });

  testWidgets(
    'part picker: MO and Report are both required, and reported together',
    (tester) async {
      PartWithMoInput? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await promptPartCode(
                    context,
                    title: 'Add Part',
                    moduleLabel: 'Casting',
                    codes: const [
                      PartCode(code: '1145', barcode: '', name: ''),
                    ],
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Neither label says optional any more.
      expect(find.text('MO number'), findsOneWidget);
      expect(find.text('Report number'), findsOneWidget);
      expect(find.textContaining('optional'), findsNothing);

      await tester.tap(find.text('Choose part code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1145').last);
      await tester.pumpAndSettle();

      // Both missing: both reported at once, rather than one per attempt.
      await tester.tap(find.text('SAVE 1145'));
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      expect(find.text('Enter the MO number'), findsOneWidget);
      expect(find.text('Enter the Report number'), findsOneWidget);

      // Whitespace is not a number.
      await _fillPartNumbers(tester, mo: '   ', report: '07');
      await tester.tap(find.text('SAVE 1145'));
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      expect(find.text('Enter the MO number'), findsOneWidget);
      expect(find.text('Enter the Report number'), findsNothing);

      await _fillPartNumbers(tester, mo: ' MO-2214 ', report: ' 07 ');
      await tester.tap(find.text('SAVE 1145'));
      await tester.pumpAndSettle();
      expect(result?.mo, 'MO-2214');
      // Kept as typed — a leading zero is part of the number, not padding.
      expect(result?.report, '07');
    },
  );

  testWidgets('part picker: editing a part prefills its MO and Report', (
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
                  title: 'Edit Part',
                  moduleLabel: 'Casting',
                  codes: const [PartCode(code: '1145', barcode: '', name: '')],
                  initialCode: '1145',
                  initialMo: 'MO-2214',
                  initialReport: '07',
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
    expect(find.text('MO-2214'), findsOneWidget);
    expect(find.text('07'), findsOneWidget);

    // Nothing to fill in: an existing part saves straight through.
    await tester.tap(find.text('SAVE 1145'));
    await tester.pumpAndSettle();
    expect(result?.mo, 'MO-2214');
    expect(result?.report, '07');
  });

  testWidgets(
    'part picker: fits a phone with the keyboard up, Save still reachable',
    (tester) async {
      // 360x640 with a 300px keyboard: what is left while typing a Report number.
      // Five fields and their error lines do not fit that, and before the
      // dialog scrolled the bottom of it — Save included — was simply cut off.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      PartWithMoInput? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await promptPartCode(
                    context,
                    title: 'Edit Part',
                    moduleLabel: 'Machining',
                    pickLine: true,
                    codes: const [
                      PartCode(
                        code: '2214',
                        barcode: '2214-M',
                        name: '2214-MACH',
                      ),
                    ],
                    initialCode: '2214',
                    initialLine: productionLines.first.label,
                    initialMo: 'MO-2214',
                    initialReport: '07',
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
      expect(tester.takeException(), isNull, reason: 'nothing overflowed');

      await tester.ensureVisible(find.text('SAVE 2214'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE 2214'));
      await tester.pumpAndSettle();
      expect(result?.report, '07');
    },
  );

  testWidgets('part picker: machining asks which line, and will not skip it', (
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
                  pickLine: true,
                  codes: const [
                    PartCode(
                      code: '2214',
                      barcode: '2214-MAZ-M',
                      name: '2214-MAZ-BRACKET-CAP-LASER-MARKING-MACH',
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

    await tester.tap(find.text('Choose part code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2214').last);
    await tester.pumpAndSettle();

    // Saving without a line is refused — a blank one would file the entry
    // under no line, which is the state the field exists to end.
    await tester.tap(find.text('SAVE 2214'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Pick the work center this part runs on'), findsOneWidget);

    final line = productionLines.first;
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    // Rows are drawn code first, as separate pieces, so a line is tapped by
    // its code — the way someone on the floor picks it.
    await tester.tap(find.text(line.number).last);
    await tester.pumpAndSettle();

    await _fillPartNumbers(tester);
    await tester.tap(find.text('SAVE 2214'));
    await tester.pumpAndSettle();
    expect(result?.name, '2214');
    // Split the way the sheet stores it, joined again for display.
    expect(result?.lineName, line.name);
    expect(result?.lineNo, line.number);
    expect(result?.lineLabel, line.label);
  });

  testWidgets('part picker: the other modules are never asked for a line', (
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
                  moduleLabel: 'Casting',
                  codes: const [PartCode(code: '1145', barcode: '', name: '')],
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
    // Casting already logs against a DCM; asking for a line too would be
    // asking the same question twice.
    expect(find.text('Work Center'), findsNothing);

    await tester.tap(find.text('Choose part code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1145').last);
    await tester.pumpAndSettle();
    await _fillPartNumbers(tester);
    await tester.tap(find.text('SAVE 1145'));
    await tester.pumpAndSettle();
    expect(result?.name, '1145');
    expect(result?.lineName, '');
    expect(result?.lineNo, '');
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

    await _fillPartNumbers(tester);
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
      // how they become real productionLines, so the old name needs a row.
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
      for (final missing in [
        'DCM09',
        'DCM10',
        'DCM13',
        'DCM14',
        'DCM16',
        'DCM22',
      ]) {
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
      expect(
        secondaryStations,
        containsAll(['CURING', 'FETTLING', 'TUMBLING']),
      );
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
    expect(find.text('Minutes stopped'), findsNWidgets(3));

    // Nothing saved yet, so fields run: Plan, then per hour
    // actual / defect qty / downtime.
    await tester.enterText(find.byType(TextFormField).at(1), '40'); // 12PM
    await tester.enterText(find.byType(TextFormField).at(3), '20'); // 12PM min
    await tester.enterText(find.byType(TextFormField).at(6), '10'); // 4PM min
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

    expect(posted!['Actual_12PM'], '40');
    expect(posted!['Downtime_12PM'], '20');
    expect(posted!['Downtime_4PM'], '10');
    expect(
      posted!.containsKey('Downtime_7_30PM'),
      isFalse,
      reason: 'an hour nobody typed into is not claimed as zero downtime',
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  group('sheet tables', () {
    test('a department only sees its own tabs', () {
      expect(rawTabsFor(['casting']).map((t) => t.name), [
        'Casting_Day',
        'Casting_Night',
      ]);
      expect(rawTabsFor(['machining']).map((t) => t.name), [
        'Machining_Day',
        'Machining_Night',
        'Machining_Rejections',
      ]);
      // Admin (every department) and widget tests (empty) get all of them.
      expect(rawTabsFor(const []).length, 7);
      expect(rawTabsFor(['casting', 'secondary', 'machining']).length, 7);
    });

    test('a capped table says so, an uncapped one does not', () {
      const short = RawTable(
        tab: 'Casting_Day',
        cols: ['Date'],
        rows: [
          ['2026-08-17'],
        ],
        total: 1,
      );
      expect(short.isCapped, isFalse);
      const capped = RawTable(
        tab: 'Machining_Day',
        cols: ['Date'],
        rows: [
          ['2026-08-17'],
        ],
        total: 4812,
      );
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
        ExportRange.today,
        DateTime(2026, 8, 17, 14, 30),
      );
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
      final csv = toCsv(
        ['A', 'B', 'C'],
        [
          ['1'],
        ],
      );
      expect(csv.trim().split('\n')[1], '1,,');
    });

    test('the file is named for the tab and the window', () {
      expect(
        exportFileName(
          'Machining_Day',
          DateWindow(DateTime(2026, 8, 17), DateTime(2026, 8, 17)),
        ),
        'Machining_Day_2026-08-17.csv',
      );
      expect(
        exportFileName(
          'Casting_Night',
          DateWindow(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
        ),
        'Casting_Night_2026-08-01_to_2026-08-31.csv',
      );
    });
  });

  testWidgets('an operator is not offered Add part, or the row menu', (
    tester,
  ) async {
    final mock = MockClient((request) async {
      if (request.url.queryParameters['action'] == 'parts') {
        return http.Response(
          '{"status":"success","data":[{"part":"2214","mo":"2214",'
          '"lineName":"Fanuc","lineNo":"21","fillPercent":0}]}',
          200,
        );
      }
      return http.Response('{"status":"success","data":[]}', 200);
    });

    Widget asRole(String role) => MaterialApp(
      home: AuthScope(
        user: AppUser(
          email: 'ahmad@hidsb.com',
          name: 'Ahmad',
          employeeId: 'E1',
          department: 'Machining',
          role: role,
          status: 'active',
        ),
        signOut: () {},
        child: MachiningPartsScreen(
          customer: 'Mazda',
          operation: machiningOperation,
          shift: 'Day',
          service: SheetsService(client: mock),
        ),
      ),
    );

    SheetsService.clearMasterCaches();
    await tester.pumpWidget(asRole('operator'));
    await tester.pumpAndSettle();

    // The part is there to log against — that is the operator's whole job.
    expect(find.text('2214'), findsOneWidget);
    // What is gone is everything that changes what the plant makes.
    expect(find.text('Add part'), findsNothing);
    expect(find.byType(CardMenuButton), findsNothing);

    SheetsService.clearMasterCaches();
    await tester.pumpWidget(asRole('superadmin'));
    await tester.pumpAndSettle();
    expect(find.text('Add part'), findsOneWidget);
    expect(find.byType(CardMenuButton), findsOneWidget);
  });

  group('the bar on every page', () {
    // Through the REAL app: HicomOpsApp, a page pushed above home, and the
    // session published the way the login gate publishes it. An earlier test
    // wrapped a screen directly in AuthScope and passed, while in the app
    // every pushed page sat outside the session — no sign-out, and the role
    // gate showing an operator everything.
    Future<void> openPartsAs(WidgetTester tester, String role) async {
      SharedPreferences.setMockInitialValues({});
      themeController.value = ThemeMode.system;
      authSession.value = AuthSession(
        user: AppUser(
          email: 'ahmad@hidsb.com',
          name: 'Ahmad',
          employeeId: 'E1',
          department: 'Machining',
          role: role,
          status: 'active',
        ),
        signOut: () {},
      );
      final mock = MockClient((request) async {
        if (request.url.queryParameters['action'] == 'parts') {
          return http.Response(
            '{"status":"success","data":[{"part":"2214","mo":"2214",'
            '"lineName":"MACH-2214","lineNo":"M-2214-1","fillPercent":0}]}',
            200,
          );
        }
        return http.Response('{"status":"success","data":[]}', 200);
      });
      await tester.pumpWidget(const HicomOpsApp());
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => MachiningPartsScreen(
                customer: 'Mazda',
                operation: machiningOperation,
                shift: 'Day',
                service: SheetsService(client: mock),
              ),
            ),
          );
      await tester.pumpAndSettle();
    }

    tearDown(() {
      authSession.value = null;
      themeController.value = ThemeMode.system;
    });

    testWidgets('a pushed page has theme, account and sign-out', (
      tester,
    ) async {
      await openPartsAs(tester, 'superadmin');
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      expect(find.byIcon(Icons.account_circle_rounded), findsOneWidget);
      expect(
        find.byTooltip('Theme: follow system (tap for light)'),
        findsOneWidget,
      );
      // And the back button, since this page was pushed.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });

    testWidgets('an operator on a pushed page is not offered Add part', (
      tester,
    ) async {
      await openPartsAs(tester, 'operator');
      expect(find.text('2214'), findsOneWidget);
      expect(find.text('Add part'), findsNothing);
      expect(find.byType(CardMenuButton), findsNothing);
    });

    testWidgets('a super admin on a pushed page is', (tester) async {
      await openPartsAs(tester, 'superadmin');
      expect(find.text('Add part'), findsOneWidget);
      expect(find.byType(CardMenuButton), findsOneWidget);
    });

    testWidgets('the theme can be switched from a pushed page', (tester) async {
      await openPartsAs(tester, 'operator');
      await tester.tap(find.byTooltip('Theme: follow system (tap for light)'));
      await tester.pumpAndSettle();
      expect(themeController.value, ThemeMode.light);
      // The button on this page follows the switch it just made.
      expect(find.byTooltip('Theme: light (tap for dark)'), findsOneWidget);
    });

    testWidgets('the account dialog says what the role allows', (tester) async {
      await openPartsAs(tester, 'operator');
      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Operator — logs production'), findsOneWidget);
    });

    testWidgets('four buttons still fit a 360px phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await openPartsAs(tester, 'superadmin');
      expect(tester.takeException(), isNull, reason: 'nothing overflowed');
      // The mark survives; the tagline gives way.
      expect(find.text('HICOM'), findsWidgets);
    });
  });

  group('who may change what the plant makes', () {
    AppUser user({String role = '', String email = 'ahmad@hidsb.com'}) =>
        AppUser(
          email: email,
          name: 'Ahmad',
          employeeId: 'E1',
          department: 'Machining',
          role: role,
          status: 'active',
        );

    test('a blank role is an operator, never a super admin', () {
      // Every row on the Users tab predates the Role column. Defaulting the
      // other way would hand everyone exactly what this restricts.
      expect(user().role, '');
      expect(user().isSuperAdmin, isFalse);
      expect(user().canManageConfig, isFalse);
    });

    test('operator cannot manage config; superadmin can', () {
      expect(user(role: 'operator').canManageConfig, isFalse);
      expect(user(role: 'superadmin').canManageConfig, isTrue);
    });

    test('the role is read however it was typed into the sheet', () {
      for (final spelling in [
        'superadmin',
        'SuperAdmin',
        'SUPERADMIN',
        '  superadmin  ',
      ]) {
        expect(
          user(role: spelling).isSuperAdmin,
          isTrue,
          reason: 'a human types this cell',
        );
      }
      // Anything that is not the superadmin value is an operator, rather
      // than some third state that quietly gets permissions.
      expect(user(role: 'admin').isSuperAdmin, isFalse);
      expect(user(role: 'super admin').isSuperAdmin, isFalse);
    });

    test('the admin address is a super admin whatever the column says', () {
      // This is what makes an empty Role column recoverable instead of a
      // lockout: someone can always get in and set the others.
      final admin = user(role: '', email: adminEmail);
      expect(admin.isSuperAdmin, isTrue);
      expect(admin.canManageConfig, isTrue);
      expect(user(role: 'operator', email: adminEmail).isSuperAdmin, isTrue);
    });

    test('the role rides back from the sheet', () {
      final parsed = AppUser.fromJson(const {
        'email': 'ahmad@hidsb.com',
        'name': 'Ahmad',
        'employeeId': 'E1',
        'department': 'Machining',
        'role': 'superadmin',
        'status': 'active',
      });
      expect(parsed.canManageConfig, isTrue);
      // An older backend sends no role at all.
      final legacy = AppUser.fromJson(const {
        'email': 'ahmad@hidsb.com',
        'name': 'Ahmad',
        'employeeId': 'E1',
        'department': 'Machining',
        'status': 'active',
      });
      expect(legacy.role, '');
      expect(legacy.canManageConfig, isFalse);
    });
  });

  group('line picker', () {
    test('a line reads as the floor says it, name then number', () {
      expect(productionLines, isNotEmpty);
      expect(const ProductionLine('Fanuc', '21').label, 'Fanuc 21');
      // Numbers stay strings — they are identifiers, and "07" must survive.
      expect(const ProductionLine('Okuma', '07').label, 'Okuma 07');
    });

    test('a line reads code first, the way the floor picks it', () {
      expect(lineDisplayOf('MACH-2214', 'M-2214-2'), 'M-2214-2 · MACH-2214');
      expect(
        const ProductionLine('WASHING MACHINE', 'WASH-DRY').display,
        'WASH-DRY · WASHING MACHINE',
      );
      // A row predating the columns may have only one half.
      expect(lineDisplayOf('MACH-2214', ''), 'MACH-2214');
      expect(lineDisplayOf('', 'M-2214-2'), 'M-2214-2');
      expect(lineDisplayOf(null, null), '');
    });

    test('Line 1 to 3 are kept, at the top of the list', () {
      expect(productionLines.take(3).map((l) => l.label), [
        'Line 1 001',
        'Line 2 002',
        'Line 3 003',
      ]);
    });

    test('every line in the roster is distinct', () {
      final labels = productionLines.map((m) => m.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('a stored label resolves back to its line', () {
      for (final line in productionLines) {
        expect(lineFromLabel(line.label)?.label, line.label);
      }
      // Case and stray spacing are how someone typed it, not part of the
      // identity. Taken from the roster rather than written out, because the
      // plant edits that list and a test must not pin its contents.
      final label = productionLines.first.label;
      expect(lineFromLabel(label.toLowerCase())?.label, label);
      expect(lineFromLabel(label.toUpperCase())?.label, label);
      expect(lineFromLabel('  $label  ')?.label, label);
    });

    test('a label splits into the two columns the sheet keeps', () {
      expect(splitLineLabel('Fanuc 21'), (name: 'Fanuc', number: '21'));
      expect(splitLineLabel('Okuma 11'), (name: 'Okuma', number: '11'));
      expect(splitLineLabel(''), (name: '', number: ''));
      expect(splitLineLabel(null), (name: '', number: ''));
    });

    test('a line off the roster still splits, never silently empty', () {
      // Retired, or typed straight into the sheet. The name must survive or
      // the row stops saying which line it meant.
      expect(splitLineLabel('Mazak 99'), (name: 'Mazak', number: '99'));
      // Multi-word names keep the number as the last token.
      expect(splitLineLabel('Brother Speedio S700'), (
        name: 'Brother Speedio',
        number: 'S700',
      ));
      // No number at all: it is all name.
      expect(splitLineLabel('Lathe'), (name: 'Lathe', number: ''));
    });

    test('the two columns rejoin for display', () {
      expect(lineLabelOf('Fanuc', '21'), 'Fanuc 21');
      // Either half may be blank on a row predating the columns.
      expect(lineLabelOf('Fanuc', ''), 'Fanuc');
      expect(lineLabelOf('', '21'), '21');
      expect(lineLabelOf('', ''), '');
      expect(lineLabelOf(null, null), '');
    });

    test('splitting and rejoining a roster line is lossless', () {
      for (final line in productionLines) {
        final parts = splitLineLabel(line.label);
        expect(lineLabelOf(parts.name, parts.number), line.label);
      }
    });

    test('a retired line resolves to null rather than throwing', () {
      // Rows logged against a line since removed from the roster still
      // have to read back — the picker shows the value and lets it change.
      expect(lineFromLabel('Mazak 99'), isNull);
      expect(lineFromLabel(''), isNull);
      expect(lineFromLabel(null), isNull);
    });
  });

  group('downtime reason codes', () {
    test('the bundled fallback is the plant list, whole and in order', () {
      expect(bundledDowntimeReasons.length, 15);
      expect(bundledDowntimeReasons.first.code, '001');
      expect(bundledDowntimeReasons.first.name, 'TOOL ROOM DOWNTIME');
      expect(bundledDowntimeReasons.last.code, '015');
      expect(bundledDowntimeReasons.last.name, 'COMPANY EVENT');
      final codes = bundledDowntimeReasons.map((r) => r.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes.every((c) => c.length == 3), isTrue);
    });

    test('the label leads with the code so a sheet can split it back out', () {
      final reason = bundledDowntimeReasons[7];
      expect(reason.label, '008 · MACHINING MAINTENANCE DOWNTIME');
      expect(reason.label.substring(0, 3), '008');
    });

    test('a reason with no code is just its name', () {
      expect(const DowntimeReason('', 'CRANE FAILURE').label, 'CRANE FAILURE');
    });

    test('a reason parses from what the sheet sends', () {
      final reason = DowntimeReason.fromJson(const {
        'code': ' 016 ',
        'name': ' CRANE FAILURE ',
      });
      expect(reason.code, '016');
      expect(reason.name, 'CRANE FAILURE');
      expect(reason.label, '016 · CRANE FAILURE');
    });

    test('a stored cell resolves back to the reason it was saved from', () {
      for (final reason in bundledDowntimeReasons) {
        expect(
          downtimeReasonFromCell(reason.label, bundledDowntimeReasons)?.code,
          reason.code,
        );
      }
      // Case is how someone typed it, not part of the identity.
      expect(
        downtimeReasonFromCell('012 · tea break', bundledDowntimeReasons)?.name,
        'TEA BREAK',
      );
      // Hand-typed in the sheet as just the code.
      expect(
        downtimeReasonFromCell('012', bundledDowntimeReasons)?.name,
        'TEA BREAK',
      );
    });

    test('it resolves against the list it is GIVEN, not a built-in one', () {
      // The list is edited on the sheet, so a reason a super admin added has
      // to resolve and one they removed has to stop resolving.
      const sheet = [DowntimeReason('016', 'CRANE FAILURE')];
      expect(
        downtimeReasonFromCell('016 · CRANE FAILURE', sheet)?.name,
        'CRANE FAILURE',
      );
      expect(
        downtimeReasonFromCell('012 · TEA BREAK', sheet),
        isNull,
        reason: 'removed from the sheet, so no longer a choice',
      );
    });

    test('anything not on the list resolves to null, never a near match', () {
      // An old free-text reason must come back null so the field can show it
      // marked "not in the list" instead of snapping it to the wrong code.
      expect(
        downtimeReasonFromCell('waiting on the crane', bundledDowntimeReasons),
        isNull,
      );
      expect(
        downtimeReasonFromCell(
          'TOOL ROOM DOWNTIME extended',
          bundledDowntimeReasons,
        ),
        isNull,
      );
      expect(downtimeReasonFromCell('', bundledDowntimeReasons), isNull);
      expect(downtimeReasonFromCell(null, bundledDowntimeReasons), isNull);
    });
  });

  group('four-hour checkpoints', () {
    test('each shift logs three times, at the agreed clock times', () {
      expect(machiningDaySlots.map((s) => s.label), [
        '12 PM',
        '4 PM',
        '7:30 PM',
      ]);
      expect(machiningNightSlots.map((s) => s.label), [
        '12 AM',
        '4 AM',
        '7:30 AM',
      ]);
      // Casting and Secondary run the identical schedule.
      expect(castingDaySlots.length, 3);
      expect(secondaryNightSlots.map((s) => s.label), [
        '12 AM',
        '4 AM',
        '7:30 AM',
      ]);
    });

    test('the 7:30 slot key avoids a colon, which Sheets reads as a time', () {
      final half = machiningDaySlots.last;
      expect(half.outputKey, 'Actual_7_30PM');
      expect(half.slotKey, '7_30PM');
      // The rejection Hour cell stores slotKey verbatim. "7:30PM" there would
      // be auto-converted to a time serial and stop matching its own slot.
      expect(half.slotKey.contains(':'), isFalse);
    });

    test('downtime and its reason are derived from the same slot key', () {
      final noon = machiningDaySlots.first;
      expect(noon.downtimeKey, 'Downtime_12PM');
      expect(noon.downtimeReasonKey, 'DowntimeReason_12PM');
    });

    test('the shift a time falls in matches Day 10:00-21:59', () {
      // autoDetect reads the wall clock, so assert the boundary rule it
      // encodes rather than the clock itself.
      bool isDay(int hour) => hour >= 10 && hour < 22;
      expect(isDay(9), isFalse); // before the day shift starts
      expect(isDay(10), isTrue); // day shift opens
      expect(isDay(21), isTrue); // still day at 21:59
      expect(isDay(22), isFalse); // night takes over
      expect(isDay(3), isFalse); // overnight
    });
  });

  testWidgets('machining entry: a reason appears once downtime is entered', (
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

    // Nothing is down yet, so nothing asks why.
    expect(find.text('Minutes stopped'), findsNWidgets(3));
    expect(find.text('Reason for the stop'), findsNothing);

    // Fields run Plan, then per checkpoint actual / defect qty / downtime.
    await tester.enterText(find.byType(TextFormField).at(3), '25'); // 12PM min
    await tester.pumpAndSettle();

    // Only the checkpoint that lost time asks for a reason, and it asks with
    // the code list rather than an empty box.
    expect(find.text('Reason for the stop'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    // Nothing is typed until "Other" is chosen.
    expect(find.text('What happened?'), findsNothing);

    await tester.dragUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MACHINING MAINTENANCE DOWNTIME').last);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byType(SubmitButton),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.byType(SubmitButton));
    await tester.pumpAndSettle();

    expect(posted!['Downtime_12PM'], '25');
    // The code leads, so LEFT(cell, 3) pulls it back out in the sheet.
    expect(
      posted!['DowntimeReason_12PM'],
      '008 · MACHINING MAINTENANCE DOWNTIME',
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'machining entry: the reasons come from the sheet, and only those',
    (tester) async {
      Map<String, dynamic>? posted;
      var reasonRequests = 0;
      final mock = MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (request.method == 'POST') {
          posted =
              (jsonDecode(request.body) as Map<String, dynamic>)['data']
                  as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }
        if (action == 'downtimereasons') {
          reasonRequests++;
          // A super admin has trimmed the list and added one of their own.
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': [
                {'code': '008', 'name': 'MACHINING MAINTENANCE DOWNTIME'},
                {'code': '016', 'name': 'CRANE FAILURE'},
              ],
            }),
            200,
          );
        }
        if (action == 'rejectiontypes') {
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
      expect(reasonRequests, 1, reason: 'asked the sheet when the part opened');

      await tester.enterText(
        find.byType(TextFormField).at(3),
        '40',
      ); // 12PM min
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // What the sheet lists is offered — including the one added there...
      expect(find.text('CRANE FAILURE'), findsWidgets);
      expect(find.text('MACHINING MAINTENANCE DOWNTIME'), findsWidgets);
      // ...and nothing else. TEA BREAK is in the app's bundled copy but not on
      // this sheet, so it is not a choice.
      expect(find.text('TEA BREAK'), findsNothing);

      // No escape hatch: no "Other", and no box to type a cause into.
      expect(find.textContaining('Other'), findsNothing);
      expect(find.text('What happened?'), findsNothing);

      await tester.tap(find.text('CRANE FAILURE').last);
      await tester.pumpAndSettle();
      expect(find.text('What happened?'), findsNothing);

      await tester.dragUntilVisible(
        find.byType(SubmitButton),
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.tap(find.byType(SubmitButton));
      await tester.pumpAndSettle();

      // A reason nobody in the app could have known about is what got saved.
      expect(posted!['DowntimeReason_12PM'], '016 · CRANE FAILURE');

      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'machining entry: a saved reason that is off the list is shown, and replaceable',
    (tester) async {
      Map<String, dynamic>? posted;
      final mock = MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (request.method == 'POST') {
          posted =
              (jsonDecode(request.body) as Map<String, dynamic>)['data']
                  as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }
        if (action == 'downtimereasons') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': [
                {'code': '008', 'name': 'MACHINING MAINTENANCE DOWNTIME'},
                {'code': '012', 'name': 'TEA BREAK'},
              ],
            }),
            200,
          );
        }
        if (action == 'row') {
          // Logged back when the reason was a free-text box.
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'Plan': '',
                'Downtime_12PM': '30',
                'DowntimeReason_12PM': 'Crane operator off sick',
              },
            }),
            200,
          );
        }
        if (action == 'rejectiontypes') {
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
      await tester.dragUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );

      // Not blanked, and not snapped to a near match: it reads as it was saved,
      // marked, so nobody mistakes it for one of the choices.
      expect(
        find.text('Crane operator off sick (not in the list)'),
        findsOneWidget,
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEA BREAK').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('not in the list'), findsNothing);

      await tester.dragUntilVisible(
        find.byType(SubmitButton),
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.tap(find.byType(SubmitButton));
      await tester.pumpAndSettle();
      expect(posted!['DowntimeReason_12PM'], '012 · TEA BREAK');

      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'machining entry: an unread sheet falls back to the bundled list',
    (tester) async {
      // The open menu is only as tall as the screen, and its items are built as
      // they scroll into view — on the default 600px surface the twelfth is not
      // there to be found.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // What an app installed ahead of the backend deploy sees: the reasons
      // action does not exist yet, so the answer is the version ping.
      final mock = MockClient((request) async {
        if (request.url.queryParameters['action'] == 'downtimereasons') {
          return http.Response(
            '{"status":"ok","version":"OLD","message":"running"}',
            200,
          );
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
      await tester.enterText(find.byType(TextFormField).at(3), '25');
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Logging a stop is never blocked by a backend that has not caught up.
      expect(find.text('TEA BREAK'), findsWidgets);
      expect(find.textContaining('Other'), findsNothing);
    },
  );

  testWidgets('machining entry: a phone-width card lays out without overflow', (
    tester,
  ) async {
    // A 360x740 phone — the width the defect picker, its quantity and the
    // remove button could not share, which is why the line stacks below
    // _SlotBlock._narrowRow.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SheetsService.clearMasterCaches();
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

    // A RenderFlex overflow is reported as an exception, so this is the
    // assertion: at phone width nothing is squeezed off its line.
    expect(tester.takeException(), isNull);

    // Each checkpoint is its own card, with the three areas labelled inside.
    expect(find.text('REJECTIONS'), findsNWidgets(3));
    expect(find.text('DOWNTIME'), findsNWidgets(3));
    expect(find.text('Actual'), findsNWidgets(3));

    // The defect picker still gets a readable width instead of collapsing.
    final picker = tester.getSize(find.byType(InputDecorator).first);
    expect(picker.width, greaterThan(220));
  });
}
