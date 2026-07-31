import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    // Day shift slots run 8 AM - 6 PM, outputs only — rejections are no longer
    // per slot but a typed list at the bottom.
    expect(find.text('Output — 8 AM'), findsOneWidget);
    expect(find.text('Output — 6 PM'), findsOneWidget);
    expect(find.text('LOR'), findsNWidgets(6));
    expect(find.textContaining('Rejection — '), findsNothing);
    expect(find.text('Rejections'), findsOneWidget);
    expect(find.text('ADD REJECTION'), findsOneWidget);

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

  testWidgets('machining entry: rejection rows can be added and removed', (
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

    expect(find.text('Qty'), findsNothing);

    await tester.dragUntilVisible(
      find.text('ADD REJECTION'),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.tap(find.text('ADD REJECTION'));
    await tester.pumpAndSettle();

    // A row is a quantity plus an unset defect-type field.
    expect(find.text('Qty'), findsOneWidget);
    expect(find.text('Select type'), findsOneWidget);
    expect(find.text('ADD ANOTHER'), findsOneWidget);

    await tester.tap(find.text('ADD ANOTHER'));
    await tester.pumpAndSettle();
    expect(find.text('Qty'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Qty'), findsOneWidget);

    // An empty row is incomplete, so there is still nothing to save.
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
