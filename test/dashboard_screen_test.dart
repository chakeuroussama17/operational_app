import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hicom_ops/screens/dashboard_screen.dart';
import 'package:hicom_ops/services/sheets_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _castingPayload() => {
  'dates': ['2026-08-03', '2026-08-04'],
  'output': [100, 150],
  'lorPercent': [33.3, 50.0],
  'byGroup': [
    {'group': '1212', 'output': 150, 'lorPercent': 50.0},
    {'group': '3131', 'output': 100, 'lorPercent': 33.3},
  ],
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

void main() {
  testWidgets('a single-department dashboard shows only that module', (
    tester,
  ) async {
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

    // KPI tiles: total output (100+150=250), best day (150, the larger).
    expect(find.text('250'), findsOneWidget);
    expect(find.text('150'), findsWidgets);
    expect(find.text('Total output'), findsOneWidget);
    expect(find.text('Best day'), findsOneWidget);
    // No rejection tiles for casting.
    expect(find.text('Rejection rate'), findsNothing);

    // The ranking bar chart, keyed by DCM for casting.
    expect(find.text('Output by DCM'), findsOneWidget);
    expect(find.text('1212'), findsOneWidget);
    expect(find.text('3131'), findsOneWidget);

    // The table-view twin.
    expect(find.text('Daily figures'), findsOneWidget);

    // Only casting — Secondary/Machining sections never rendered.
    expect(find.text('Secondary'), findsNothing);
    expect(find.text('Machining'), findsNothing);
  });

  testWidgets('machining adds a rejection KPI row and a defect breakdown', (
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
    // 28 total rejections (8+20) over 178 total pieces (150 output + 28
    // rejects) = 15.7%.
    expect(find.text('15.7'), findsOneWidget);

    // The composition donut and the matching ranked list, same data.
    expect(find.text('Defect composition'), findsOneWidget);
    expect(find.text('Defects by type'), findsOneWidget);
    expect(find.text('OTHERS MACH'), findsWidgets);
    expect(find.text('POROSITY'), findsWidgets);

    // Daily figures table gains the Rejects column.
    expect(find.text('Rejects'), findsOneWidget);
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
                },
                'machining': _machiningPayload(),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Three full dashboards stacked (KPIs, three charts, a ranking bar, a
    // table apiece) run well past one screen — the Sliver only builds what's
    // in range, so drag each next header into view before asserting on it.
    final list = find.byKey(const ValueKey('dashboardScrollList'));
    expect(find.text('Casting'), findsOneWidget);
    for (var i = 0; i < 6 && find.text('Secondary').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump();
    }
    expect(find.text('Secondary'), findsOneWidget);
    for (var i = 0; i < 6 && find.text('Machining').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump();
    }
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
