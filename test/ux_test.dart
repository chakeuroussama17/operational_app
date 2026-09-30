import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hicom_ops/models/analytics_models.dart';
import 'package:hicom_ops/models/machining_models.dart';
import 'package:hicom_ops/screens/machining_entry_screen.dart';
import 'package:hicom_ops/screens/machining_parts_screen.dart';
import 'package:hicom_ops/services/sheets_service.dart';
import 'package:hicom_ops/widgets/submission_feedback.dart';
import 'package:hicom_ops/widgets/today_scoreboard.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hicom_ops/models/shift_progress.dart';
import 'package:hicom_ops/widgets/checkpoint_timeline.dart';
import 'package:hicom_ops/widgets/module_shell.dart';

const _day = [
  TimelineCheckpoint(label: '12 PM', slotKey: '12PM', logged: false),
  TimelineCheckpoint(label: '4 PM', slotKey: '4PM', logged: false),
  TimelineCheckpoint(label: '7:30 PM', slotKey: '7_30PM', logged: false),
];

const _night = [
  TimelineCheckpoint(label: '12 AM', slotKey: '12AM', logged: false),
  TimelineCheckpoint(label: '4 AM', slotKey: '4AM', logged: false),
  TimelineCheckpoint(label: '7:30 AM', slotKey: '7_30AM', logged: false),
];

List<TimelineCheckpoint> _logged(List<TimelineCheckpoint> all, Set<int> which) => [
  for (var i = 0; i < all.length; i++)
    TimelineCheckpoint(
      label: all[i].label,
      slotKey: all[i].slotKey,
      logged: which.contains(i),
    ),
];

void main() {
  group('checkpoint clock', () {
    test('slot keys read as clock times, 12 o\'clock included', () {
      expect(checkpointClock('12PM'), (hour: 12, minute: 0));
      expect(checkpointClock('4PM'), (hour: 16, minute: 0));
      expect(checkpointClock('7_30PM'), (hour: 19, minute: 30));
      expect(checkpointClock('12AM'), (hour: 0, minute: 0));
      expect(checkpointClock('7_30AM'), (hour: 7, minute: 30));
      expect(checkpointClock('Actual_12PM'), isNull);
    });

    test('Day is 10:00-21:59, Night the rest', () {
      expect(currentShiftAt(DateTime(2026, 9, 30, 9, 59)), 'Night');
      expect(currentShiftAt(DateTime(2026, 9, 30, 10)), 'Day');
      expect(currentShiftAt(DateTime(2026, 9, 30, 21, 59)), 'Day');
      expect(currentShiftAt(DateTime(2026, 9, 30, 22)), 'Night');
    });

    test('a night checkpoint belongs to the morning after the evening start', () {
      // 23:00 on the 30th: the 12 AM checkpoint is the 1st, not the 30th.
      expect(
        checkpointTime('12AM', 'Night', DateTime(2026, 9, 30, 23)),
        DateTime(2026, 10, 1),
      );
      // 02:00 on the 1st: the same checkpoint is today, already past.
      expect(
        checkpointTime('12AM', 'Night', DateTime(2026, 10, 1, 2)),
        DateTime(2026, 10, 1),
      );
    });
  });

  group('checkpoint states', () {
    test('the next one is due, the ones after are upcoming', () {
      final states = checkpointStates(_day, 'Day', DateTime(2026, 9, 30, 11));
      expect(states, [
        CheckpointState.due,
        CheckpointState.upcoming,
        CheckpointState.upcoming,
      ]);
    });

    test('logged beats everything; a missed one is overdue after the grace', () {
      final now = DateTime(2026, 9, 30, 16, 45); // 4 PM + 45 min
      final states = checkpointStates(_logged(_day, {}), 'Day', now);
      expect(states[0], CheckpointState.overdue);
      expect(states[1], CheckpointState.overdue);
      expect(states[2], CheckpointState.due);

      final some = checkpointStates(_logged(_day, {0}), 'Day', now);
      expect(some[0], CheckpointState.done);
    });

    test('within the grace window it is still due, not overdue', () {
      final states = checkpointStates(
        _logged(_day, {0}),
        'Day',
        DateTime(2026, 9, 30, 16, 20),
      );
      expect(states[1], CheckpointState.due);
    });

    test('the shift nobody is working shows logged vs not, and no deadlines', () {
      // Looking at Night's form at 11 AM: nothing about Night is due now.
      final states = checkpointStates(
        _logged(_night, {0}),
        'Night',
        DateTime(2026, 9, 30, 11),
      );
      expect(states, [
        CheckpointState.done,
        CheckpointState.idle,
        CheckpointState.idle,
      ]);
    });

    test('night, just after midnight: 12 AM due, the rest upcoming', () {
      final states = checkpointStates(_night, 'Night', DateTime(2026, 10, 1, 0, 10));
      expect(states.first, CheckpointState.due);
      expect(states.last, CheckpointState.upcoming);
    });

    test('the countdown reads the way someone would say it', () {
      final at = DateTime(2026, 9, 30, 16);
      expect(dueText(at, DateTime(2026, 9, 30, 14, 40)), 'in 1h 20m');
      expect(dueText(at, DateTime(2026, 9, 30, 15)), 'in 1h');
      expect(dueText(at, DateTime(2026, 9, 30, 15, 45)), 'in 15m');
      expect(dueText(at, DateTime(2026, 9, 30, 16, 5)), 'due now');
    });
  });

  group('pace', () {
    ShiftProgress p({double? plan, double actual = 0, int filled = 0}) =>
        ShiftProgress(
          plan: plan,
          actual: actual,
          downtime: 0,
          filled: filled,
          total: 3,
        );

    test('judged against the plan\'s share for the checkpoints logged', () {
      // One of three logged: a third of 900 is on pace.
      expect(p(plan: 900, actual: 300, filled: 1).health, PaceHealth.onPace);
      expect(p(plan: 900, actual: 260, filled: 1).health, PaceHealth.behind);
      expect(p(plan: 900, actual: 150, filled: 1).health, PaceHealth.wellBehind);
    });

    test('five percent of slack before "behind"', () {
      expect(p(plan: 900, actual: 285, filled: 1).health, PaceHealth.onPace);
      expect(p(plan: 900, actual: 284, filled: 1).health, PaceHealth.behind);
    });

    test('every checkpoint in and the plan met is complete', () {
      expect(p(plan: 900, actual: 910, filled: 3).health, PaceHealth.complete);
      expect(p(plan: 900, actual: 600, filled: 3).health, PaceHealth.wellBehind);
    });

    test('no plan, or nothing logged, is unknown — not green', () {
      expect(p(actual: 500, filled: 2).health, PaceHealth.unknown);
      expect(p(plan: 900).health, PaceHealth.unknown);
    });

    test('an older backend without the fields gives no progress at all', () {
      expect(ShiftProgress.fromJson(const {'fillPercent': 33}), isNull);
      final parsed = ShiftProgress.fromJson(const {
        'plan': 900,
        'actual': 300,
        'downtime': 20,
        'slotsFilled': 1,
        'slotsTotal': 3,
      })!;
      expect(parsed.health, PaceHealth.onPace);
      expect(parsed.downtime, 20);
    });
  });

  group('rendered', () {
    testWidgets('the timeline shows logged, the countdown, and what was missed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckpointTimeline(
              shift: 'Day',
              checkpoints: _logged(_day, {0}),
              clock: () => DateTime(2026, 9, 30, 14, 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('logged'), findsOneWidget);
      expect(find.text('in 1h 20m'), findsOneWidget);
    });

    testWidgets('a part card says whether it is on pace, and shows downtime', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectorCard(
              title: '2214',
              subtitle: 'MO 2214',
              icon: Icons.tag_rounded,
              onTap: () {},
              fillPercent: 33,
              progress: const ShiftProgress(
                plan: 900,
                actual: 300,
                downtime: 20,
                filled: 1,
                total: 3,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('300 of 900 · on pace'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget, reason: 'the ring');
      // The plain bar is replaced, not shown twice.
      expect(find.text('33% logged'), findsNothing);
    });

    testWidgets('without progress the card keeps its plain bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectorCard(
              title: '2214',
              subtitle: 'MO 2214',
              icon: Icons.tag_rounded,
              onTap: () {},
              fillPercent: 33,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('33% logged'), findsOneWidget);
      expect(find.byType(PaceRing), findsNothing);
    });
  });

  group('motion', () {
    testWidgets('a list that is loading shows its shape, not a spinner', (
      tester,
    ) async {
      final gate = Completer<http.Response>();
      await tester.pumpWidget(
        MaterialApp(
          home: MachiningPartsScreen(
            customer: 'Mazda',
            operation: machiningOperation,
            shift: 'Day',
            service: SheetsService(client: MockClient((_) => gate.future)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete(http.Response('{"status":"success","data":[]}', 200));
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonList), findsNothing);
    });

    testWidgets('a save is felt as well as seen', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add('${call.method}:${call.arguments}');
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSaveSuccessSnack(context),
                child: const Text('save'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(calls, contains('HapticFeedback.vibrate:HapticFeedbackType.mediumImpact'));
      expect(find.text('Saved successfully'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a part card and the form it opens share a hero tag', (
      tester,
    ) async {
      final mock = MockClient((request) async {
        if (request.url.queryParameters['action'] == 'parts') {
          return http.Response(
            '{"status":"success","data":[{"part":"2214","lineNo":"M-2214-1",'
            '"lineName":"MACH-2214","fillPercent":0}]}',
            200,
          );
        }
        return http.Response('{"status":"success","data":null}', 200);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MachiningPartsScreen(
            customer: 'Mazda',
            operation: machiningOperation,
            shift: 'Day',
            service: SheetsService(client: mock),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const tag = 'part:machining:machining:Mazda:2214:M-2214-1';
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == tag),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MachiningEntryScreen(
            customer: 'Mazda',
            part: '2214',
            operation: machiningOperation,
            shift: 'Day',
            heroTag: tag,
            service: SheetsService(client: mock),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == tag),
        findsOneWidget,
        reason: 'the landing spot for the chip on the card',
      );
    });
  });

  group('today scoreboard', () {
    AnalyticsSeries week(List<double> output, {List<double> plan = const []}) =>
        AnalyticsSeries(
          dates: [for (var i = 0; i < output.length; i++) '2026-09-2$i'],
          output: output,
          lorPercent: [for (final _ in output) 80.0],
          plan: plan,
        );

    test('big numbers are grouped so they read at a glance', () {
      expect(groupThousands(0), '0');
      expect(groupThousands(999), '999');
      expect(groupThousands(12480), '12,480');
      expect(groupThousands(1234567), '1,234,567');
    });

    testWidgets('today is the last day of the week, summed across modules', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodayScoreboard(
              modules: const ['casting', 'machining'],
              loading: false,
              series: {
                'casting': week([900, 1000, 4000], plan: [0, 0, 5000]),
                'machining': week([100, 200, 2000], plan: [0, 0, 2500]),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 4,000 + 2,000 today — not the week's total.
      expect(find.text('6,000'), findsOneWidget);
      expect(find.text('of 7,500 planned · 80%'), findsOneWidget);
    });

    testWidgets('no plan says so rather than drawing a bar against zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodayScoreboard(
              modules: const ['casting'],
              loading: false,
              series: {'casting': week([10, 20, 30])},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No plan set for today yet'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('while loading it shows a dash, not a zero', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TodayScoreboard(
              modules: ['casting'],
              loading: true,
              series: {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('—'), findsWidgets);
      expect(find.text('0'), findsNothing);
    });
  });
}
