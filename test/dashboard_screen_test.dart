import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hicom_ops/screens/dashboard_screen.dart';
import 'package:hicom_ops/services/sheets_service.dart';
import 'package:hicom_ops/widgets/filter_chip_row.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Two DCMs over two days. 1212 runs parts A1+A2, 3131 runs A1 only, so the
/// part ranking differs depending on whether a machine filter is applied.
Map<String, dynamic> _castingPayload() => {
  'dates': ['2026-08-03', '2026-08-04'],
  'output': [100, 150],
  'lorPercent': [33.3, 50.0],
  'byGroup': [
    {'group': '1212', 'output': 180, 'lorPercent': 60.0},
    {'group': '3131', 'output': 70, 'lorPercent': 25.0},
  ],
  'parts': [
    {
      'group': '1212',
      'part': 'A1',
      'name': 'ARM-LH',
      'output': 140,
      'lorPercent': 70.0,
    },
    {
      'group': '1212',
      'part': 'A2',
      'name': 'ARM-RH',
      'output': 40,
      'lorPercent': 20.0,
    },
    {
      'group': '3131',
      'part': 'A1',
      'name': 'ARM-LH',
      'output': 70,
      'lorPercent': 25.0,
    },
  ],
  'byShift': [
    {'shift': 'Day', 'output': 190, 'lorPercent': 55.0},
    {'shift': 'Night', 'output': 60, 'lorPercent': 20.0},
  ],
  'shiftSeries': {
    'Day': [80, 110],
    'Night': [20, 40],
  },
  'groupSeries': {
    '1212': [70, 110],
    '3131': [30, 40],
  },
  'groupLorSeries': {
    '1212': [40.0, 60.0],
    '3131': [null, 25.0],
  },
};

Map<String, dynamic> _machiningPayload() => {
  'dates': ['2026-08-03', '2026-08-04'],
  'output': [90, 60],
  'lorPercent': [30.0, 50.0],
  'rejection': [8, 20],
  'byGroup': [
    {'group': 'Mazda', 'output': 100, 'lorPercent': 40.0},
    {'group': 'Proton', 'output': 50, 'lorPercent': 20.0},
  ],
  'parts': [
    // Mazda M1: lots of output, few rejects -> low rate.
    {
      'group': 'Mazda',
      'part': 'M1',
      'name': 'BRKT-LH',
      'output': 100,
      'rejection': 4,
    },
    // Proton M2: little output, many rejects -> the real problem.
    {
      'group': 'Proton',
      'part': 'M2',
      'name': 'BRKT-RH',
      'output': 50,
      'rejection': 24,
    },
  ],
  'byShift': [
    {'shift': 'Day', 'output': 150, 'lorPercent': 40.0},
    {'shift': 'Night', 'output': 0, 'lorPercent': null},
  ],
  'shiftSeries': {
    'Day': [90, 60],
    'Night': [0, 0],
  },
  'groupSeries': {
    'Mazda': [60, 40],
    'Proton': [30, 20],
  },
  'groupLorSeries': {
    'Mazda': [30.0, 40.0],
    'Proton': [20.0, 20.0],
  },
  'rejectionsByType': [
    {'type': 'OTHERS MACH', 'qty': 20},
    {'type': 'POROSITY', 'qty': 5},
    {'type': 'FLASHES', 'qty': 3},
  ],
};

SheetsService _mockService({
  required Map<String, Map<String, dynamic>> byModule,
}) {
  return SheetsService(
    client: MockClient((request) async {
      final module = request.url.queryParameters['module'];
      final payload = byModule[module];
      if (payload == null) {
        return http.Response('{"status":"error","message":"unknown"}', 400);
      }
      return http.Response(
        jsonEncode({'status': 'success', 'data': payload}),
        200,
      );
    }),
  );
}

Future<void> _pumpCasting(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          modules: const ['casting'],
          service: _mockService(byModule: {'casting': _castingPayload()}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drags the dashboard list until [target] is built, or gives up.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final list = find.byKey(const ValueKey('dashboardScrollList'));
  for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -600));
    await tester.pump();
  }
}

void main() {
  testWidgets('a single-department dashboard shows only that module', (
    tester,
  ) async {
    await _pumpCasting(tester);

    // KPI tiles: total output over the window (100+150).
    expect(find.text('250'), findsOneWidget);
    expect(find.text('Total output'), findsOneWidget);
    expect(find.text('Best day'), findsOneWidget);
    expect(find.text('Parts running'), findsOneWidget);
    // No rejection tiles for casting.
    expect(find.text('Rejection rate'), findsNothing);

    // Only casting — Secondary/Machining sections never rendered.
    expect(find.text('Secondary'), findsNothing);
    expect(find.text('Machining'), findsNothing);
  });

  testWidgets('casting: shift comparison, ranking and part charts', (
    tester,
  ) async {
    await _pumpCasting(tester);

    await _scrollTo(tester, find.text('Day vs Night'));
    expect(find.text('Day vs Night'), findsOneWidget);
    expect(find.text('190'), findsOneWidget, reason: 'day total');
    expect(find.text('60'), findsOneWidget, reason: 'night total');
    expect(find.textContaining('Day carries 76%'), findsOneWidget);

    await _scrollTo(tester, find.text('Output per shift'));
    expect(find.text('Output per shift'), findsOneWidget);
    // Two series must carry a legend, never colour alone.
    expect(find.text('Day'), findsWidgets);
    expect(find.text('Night'), findsWidgets);

    await _scrollTo(tester, find.text('Output by DCM'));
    expect(find.text('Output by DCM'), findsOneWidget);

    await _scrollTo(tester, find.text('Output by part'));
    expect(find.text('Output by part'), findsOneWidget);
    // Unfiltered, A1 is summed across both DCMs: 140 + 70. Appears twice —
    // once on the bar, once in the Parts table twin below it.
    expect(find.text('210'), findsWidgets);
    expect(find.text('ARM-LH'), findsWidgets);
  });

  testWidgets('a part running on several machines says so, not blank', (
    tester,
  ) async {
    await _pumpCasting(tester);
    await _scrollTo(tester, find.text('Parts'));

    // A1 runs on both 1212 and 3131, so naming one would be wrong and
    // leaving it blank would read as missing data.
    expect(find.text('2 DCMs'), findsOneWidget);
    // A2 runs on 1212 alone and still names it.
    expect(find.text('1212'), findsWidgets);
  });

  testWidgets('picking a machine rescopes the trends, KPIs and parts', (
    tester,
  ) async {
    await _pumpCasting(tester);

    // Unfiltered first: 250 across both DCMs.
    expect(find.text('250'), findsOneWidget);
    expect(find.text('Output'), findsWidgets);

    // "1212" also labels a bar and a table cell — target the filter chip.
    await tester.tap(
      find.descendant(
        of: find.byType(FilterChipRow),
        matching: find.text('1212'),
      ),
    );
    await tester.pumpAndSettle();

    // KPI and chart titles both say what they are now scoped to, so a
    // filtered chart can't be mistaken for a department-wide one.
    // On the KPI tile and again on 1212's own bar in the DCM ranking.
    expect(find.text('180'), findsWidgets, reason: '1212 total = 70 + 110');
    expect(find.text('250'), findsNothing);
    expect(find.text('Output — DCM 1212'), findsOneWidget);
    expect(find.text('LOR% — DCM 1212'), findsOneWidget);

    await _scrollTo(tester, find.text('Output by part — DCM 1212'));
    expect(find.text('Output by part — DCM 1212'), findsOneWidget);
    // 1212's own parts only — A1 is now 140, not the cross-machine 210.
    expect(find.text('140'), findsWidgets);
    expect(find.text('210'), findsNothing);

    // The cross-machine ranking survives the filter (emphasis, not removal)
    // so you can still see where the picked machine sits.
    expect(find.text('Output by DCM'), findsOneWidget);
  });

  testWidgets('machining adds rejection KPIs, a breakdown and rate ranking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            modules: const ['machining'],
            service: _mockService(byModule: {'machining': _machiningPayload()}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total rejections'), findsOneWidget);
    expect(find.text('Rejection rate'), findsOneWidget);
    // 28 rejects over 178 total pieces (150 output + 28) = 15.7%.
    expect(find.text('15.7'), findsOneWidget);

    await _scrollTo(tester, find.text('Defect composition'));
    expect(find.text('Defect composition'), findsOneWidget);
    expect(find.text('OTHERS MACH'), findsWidgets);

    await _scrollTo(tester, find.text('Rejections by part'));
    expect(find.text('Rejections by part'), findsOneWidget);

    // Count alone would rank M2 above M1 anyway here, but the RATE chart is
    // the one that says M2 is scrapping a third of everything it makes.
    await _scrollTo(tester, find.text('Worst rejection rate'));
    expect(find.text('Worst rejection rate'), findsOneWidget);
    // On the bar and again in the Parts table's Rate column.
    expect(find.text('32.4%'), findsWidgets, reason: '24 of 74 for M2');
  });

  testWidgets('the admin (no modules filter) sees all three sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            service: _mockService(
              byModule: {
                'casting': _castingPayload(),
                'secondary': {
                  'dates': ['2026-08-04'],
                  'output': [30],
                  'lorPercent': [30.0],
                  'byGroup': [
                    {'group': 'ST1', 'output': 30, 'lorPercent': 30.0},
                  ],
                  'parts': [
                    {'group': 'ST1', 'part': 'P7', 'name': '', 'output': 30},
                  ],
                  'byShift': [
                    {'shift': 'Day', 'output': 30, 'lorPercent': 30.0},
                    {'shift': 'Night', 'output': 0, 'lorPercent': null},
                  ],
                  'shiftSeries': {
                    'Day': [30],
                    'Night': [0],
                  },
                  'groupSeries': {
                    'ST1': [30],
                  },
                  'groupLorSeries': {
                    'ST1': [30.0],
                  },
                },
                'machining': _machiningPayload(),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Casting'), findsOneWidget);
    await _scrollTo(tester, find.text('Secondary'));
    expect(find.text('Secondary'), findsOneWidget);
    await _scrollTo(tester, find.text('Machining'));
    expect(find.text('Machining'), findsOneWidget);
  });

  testWidgets('an empty window shows empty states, not a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            modules: const ['casting'],
            service: _mockService(
              byModule: {
                'casting': {
                  'dates': ['2026-08-04'],
                  'output': [0],
                  'lorPercent': [null],
                  'byGroup': <Map<String, dynamic>>[],
                  'parts': <Map<String, dynamic>>[],
                },
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No data logged yet in this window'), findsWidgets);
    // KPIs fall back to placeholders rather than throwing on an empty series.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets(
    'switching the date range keeps old data visible while it reloads',
    (tester) async {
      var calls = 0;
      final service = SheetsService(
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({'status': 'success', 'data': _castingPayload()}),
            200,
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(modules: const ['casting'], service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);

      await tester.tap(find.text('30D'));
      // Mid-flight: the previous numbers are still on screen (dimmed), not a
      // blank skeleton.
      await tester.pump();
      expect(find.text('250'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
