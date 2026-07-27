import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hicom_ops/services/sheets_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('casting incremental API (shift-aware)', () {
    test('dashboard: parses a bare list, passes action+shift params', () async {
      late Uri requested;
      final service = SheetsService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '[{"dcm":"1212","lastUpdated":"14:32"},{"dcm":"3131","lastUpdated":null}]',
            200,
          );
        }),
      );

      final machines = await service.fetchCastingDashboard(shift: 'Day');

      expect(requested.queryParameters, {
        'action': 'dashboard',
        'shift': 'Day',
      });
      expect(machines, hasLength(2));
      expect(machines[0].dcm, '1212');
      expect(machines[0].lastUpdated, '14:32');
      expect(machines[1].lastUpdated, isNull);
    });

    test(
      'parts: parses envelope form + MO, clamps and rounds fillPercent',
      () async {
        late Uri requested;
        final service = SheetsService(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response(
              '{"status":"ok","data":['
              '{"part":1,"mo":"JUL-0451","lastUpdated":"09:15","fillPercent":"33.4"},'
              '{"part":"2","lastUpdated":null,"fillPercent":140}]}',
              200,
            );
          }),
        );

        final parts = await service.fetchCastingParts('1212', shift: 'Night');

        expect(requested.queryParameters, {
          'action': 'parts',
          'dcm': '1212',
          'shift': 'Night',
        });
        expect(parts[0].part, '1');
        expect(parts[0].mo, 'JUL-0451');
        expect(parts[0].fillPercent, 33);
        expect(parts[1].mo, isNull);
        expect(parts[1].fillPercent, 100);
        expect(parts[1].lastUpdated, isNull);
      },
    );

    test('row: returns null when backend envelopes a null data', () async {
      final service = SheetsService(
        client: MockClient(
          (request) async =>
              http.Response('{"status":"success","data":null}', 200),
        ),
      );

      final row = await service.fetchCastingRow(
        dcm: '1212',
        part: '1',
        shift: 'Day',
      );

      expect(row, isNull);
    });

    test(
      'row: unwraps the data envelope, normalises numbers, formats LOR',
      () async {
        late Uri requested;
        final service = SheetsService(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response(
              '{"status":"success","data":{"Date":"2026-07-17","DCM":1212,'
              '"PartNo":3,"Shift":"Day","MO":"JUL-0451","Plan":300,'
              '"Output_10AM":30,"Output_LOR10AM":0.1,"Output_12PM":45,'
              '"Output_LOR12PM":0.15,"Output_2PM":"","Output_LOR2PM":"",'
              '"LastUpdated":"14:32"}}',
              200,
            );
          }),
        );

        final row = await service.fetchCastingRow(
          dcm: '1212',
          part: '3',
          shift: 'Day',
        );

        expect(requested.queryParameters, {
          'action': 'row',
          'dcm': '1212',
          'part': '3',
          'shift': 'Day',
        });
        expect(row!.value('Plan'), '300');
        expect(row.value('MO'), 'JUL-0451');
        expect(row.value('Output_10AM'), '30');
        // Sheets returns LOR as a fraction; the badge shows a percentage.
        expect(row.lorLabel('Output_LOR10AM'), '10%');
        expect(row.lorLabel('Output_LOR12PM'), '15%');
        expect(row.value('Output_12PM'), '45');
        expect(row.value('Output_2PM'), isNull); // blank cell
        expect(row.value('Output_4PM'), isNull); // absent cell
      },
    );

    test('lorLabel keeps an explicit percent string as-is', () async {
      final service = SheetsService(
        client: MockClient(
          (request) async => http.Response(
            '{"status":"success","data":{"DCM":"1212","PartNo":"1",'
            '"Output_LOR10AM":"33%"}}',
            200,
          ),
        ),
      );

      final row = await service.fetchCastingRow(
        dcm: '1212',
        part: '1',
        shift: 'Day',
      );

      expect(row!.lorLabel('Output_LOR10AM'), '33%');
    });

    test(
      'submit: posts secret + only the provided fields, including Shift',
      () async {
        late Map<String, dynamic> sent;
        final service = SheetsService(
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{"status":"success"}', 200);
          }),
        );

        await service.submitCastingUpdate({
          'DCM': '1212',
          'PartNo': '1',
          'Shift': 'Night',
          'Plan': '300',
          'Output_8PM': '30',
        });

        expect(sent['secret'], 'hicom2026changeme');
        expect(sent['module'], 'casting');
        expect(sent['data'], {
          'DCM': '1212',
          'PartNo': '1',
          'Shift': 'Night',
          'Plan': '300',
          'Output_8PM': '30',
        });
      },
    );

    test(
      'addCastingPart: posts the castingAddPart op with group/part/mo',
      () async {
        late Map<String, dynamic> sent;
        final service = SheetsService(
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{"status":"success"}', 200);
          }),
        );

        await service.addCastingPart(dcm: '1212', part: '11', mo: 'JUL-0451');

        expect(sent['action'], 'config');
        expect(sent['op'], 'castingAddPart');
        expect(sent['group'], '1212');
        expect(sent['part'], '11');
        expect(sent['mo'], 'JUL-0451');
      },
    );

    test(
      'editCastingPart: omits mo when left unset (leaves it unchanged)',
      () async {
        late Map<String, dynamic> sent;
        final service = SheetsService(
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{"status":"success"}', 200);
          }),
        );

        await service.editCastingPart(dcm: '1212', part: '1', newPart: '1');

        expect(sent['op'], 'castingEditPart');
        expect(sent['newPart'], '1');
        expect(sent.containsKey('mo'), isFalse);
      },
    );

    test('GET surfaces an explicit error envelope', () async {
      final service = SheetsService(
        client: MockClient(
          (request) async =>
              http.Response('{"status":"error","message":"Unknown DCM"}', 200),
        ),
      );

      await expectLater(
        service.fetchCastingParts('9999', shift: 'Day'),
        throwsA(
          isA<SheetsSubmissionException>().having(
            (e) => e.message,
            'message',
            'Unknown DCM',
          ),
        ),
      );
    });
  });

  group('secondary incremental API (shift-aware)', () {
    test('dashboard: passes action+module+shift, maps dcm->station', () async {
      late Uri requested;
      final service = SheetsService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '[{"dcm":"ST1","lastUpdated":"14:32"},{"dcm":"ST2","lastUpdated":null}]',
            200,
          );
        }),
      );

      final stations = await service.fetchSecondaryDashboard(shift: 'Day');

      expect(requested.queryParameters, {
        'action': 'dashboard',
        'module': 'secondary',
        'shift': 'Day',
      });
      expect(stations, hasLength(2));
      expect(stations[0].station, 'ST1');
      expect(stations[0].lastUpdated, '14:32');
      expect(stations[1].lastUpdated, isNull);
    });

    test('parts: parses MO + shift param, clamps fillPercent', () async {
      late Uri requested;
      final service = SheetsService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"status":"ok","data":['
            '{"part":"P1","mo":"SEC-01","lastUpdated":"09:15","fillPercent":"33.4"},'
            '{"part":"P2","lastUpdated":null,"fillPercent":140}]}',
            200,
          );
        }),
      );

      final parts = await service.fetchSecondaryParts('ST1', shift: 'Night');

      expect(requested.queryParameters, {
        'action': 'parts',
        'module': 'secondary',
        'station': 'ST1',
        'shift': 'Night',
      });
      expect(parts[0].part, 'P1');
      expect(parts[0].mo, 'SEC-01');
      expect(parts[0].fillPercent, 33);
      expect(parts[1].mo, isNull);
      expect(parts[1].fillPercent, 100);
    });

    test('row: passes shift, normalises numbers, formats LOR', () async {
      late Uri requested;
      final service = SheetsService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"status":"success","data":{"Date":"2026-07-27","Station":"ST1",'
            '"PartNo":"P1","MO":"SEC-01","Plan":100,'
            '"Actual_8AM":20,"LOR_8AM":0.2,"Actual_10AM":"","LOR_10AM":"",'
            '"LastUpdated":"14:32"}}',
            200,
          );
        }),
      );

      final row = await service.fetchSecondaryRow(
        station: 'ST1',
        part: 'P1',
        shift: 'Day',
      );

      expect(requested.queryParameters, {
        'action': 'row',
        'module': 'secondary',
        'station': 'ST1',
        'part': 'P1',
        'shift': 'Day',
      });
      expect(row!.value('Plan'), '100');
      expect(row.value('MO'), 'SEC-01');
      expect(row.value('Actual_8AM'), '20');
      expect(row.lorLabel('LOR_8AM'), '20%');
      expect(row.value('Actual_10AM'), isNull);
    });

    test('submit: posts module=secondary and includes Shift', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.submitSecondaryUpdate({
        'Station': 'ST1',
        'PartNo': 'P1',
        'Shift': 'Night',
        'Plan': '100',
        'Actual_8PM': '35',
      });

      expect(sent['module'], 'secondary');
      expect(sent['data'], {
        'Station': 'ST1',
        'PartNo': 'P1',
        'Shift': 'Night',
        'Plan': '100',
        'Actual_8PM': '35',
      });
    });

    test('addSecondaryPart: posts the secondaryAddPart op with mo', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.addSecondaryPart(station: 'ST1', part: 'P4', mo: 'SEC-04');

      expect(sent['action'], 'config');
      expect(sent['op'], 'secondaryAddPart');
      expect(sent['group'], 'ST1');
      expect(sent['part'], 'P4');
      expect(sent['mo'], 'SEC-04');
    });

    test('editSecondaryPart: omits mo when left unset', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.editSecondaryPart(
        station: 'ST1',
        part: 'P1',
        newPart: 'P1',
      );

      expect(sent['op'], 'secondaryEditPart');
      expect(sent['newPart'], 'P1');
      expect(sent.containsKey('mo'), isFalse);
    });
  });

  group('machining incremental API', () {
    test('dashboard: passes module param, parses customer cards', () async {
      late Uri requested;
      final service = SheetsService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"status":"success","data":['
            '{"dcm":"Mazda","lastUpdated":"10:10"},'
            '{"dcm":"Proton","lastUpdated":null}]}',
            200,
          );
        }),
      );

      final customers = await service.fetchMachiningDashboard();

      expect(requested.queryParameters, {
        'action': 'dashboard',
        'module': 'machining',
      });
      expect(customers, hasLength(2));
      expect(customers[0].customer, 'Mazda');
      expect(customers[0].lastUpdated, '10:10');
      expect(customers[1].lastUpdated, isNull);
    });

    test(
      'parts: passes customer param, parses part cards (no fillPercent)',
      () async {
        late Uri requested;
        final service = SheetsService(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response(
              '{"status":"success","data":['
              '{"part":"1","lastUpdated":"08:00"},'
              '{"part":"2","lastUpdated":null}]}',
              200,
            );
          }),
        );

        final parts = await service.fetchMachiningParts('Mazda');

        expect(requested.queryParameters, {
          'action': 'parts',
          'module': 'machining',
          'customer': 'Mazda',
        });
        expect(parts[0].part, '1');
        expect(parts[0].lastUpdated, '08:00');
        expect(parts[1].lastUpdated, isNull);
      },
    );

    test('lines: passes customer+part params, clamps fillPercent', () async {
      late Uri requested;
      final service = SheetsService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"status":"success","data":['
            '{"part":"Line 1","lastUpdated":"09:00","fillPercent":"33.4"},'
            '{"part":"Line 2","lastUpdated":null,"fillPercent":140}]}',
            200,
          );
        }),
      );

      final lines = await service.fetchMachiningLines(
        customer: 'Mazda',
        part: '1',
      );

      expect(requested.queryParameters, {
        'action': 'lines',
        'module': 'machining',
        'customer': 'Mazda',
        'part': '1',
      });
      expect(lines[0].line, 'Line 1');
      expect(lines[0].fillPercent, 33);
      expect(lines[1].fillPercent, 100);
      expect(lines[1].lastUpdated, isNull);
    });

    test('row: returns null when backend envelopes a null data', () async {
      final service = SheetsService(
        client: MockClient(
          (request) async =>
              http.Response('{"status":"success","data":null}', 200),
        ),
      );

      final row = await service.fetchMachiningRow(
        customer: 'Mazda',
        part: '1',
        line: 'Line 1',
      );

      expect(row, isNull);
    });

    test(
      'row: unwraps envelope, normalises numbers, formats LOR and Rejection',
      () async {
        late Uri requested;
        final service = SheetsService(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response(
              '{"status":"success","data":{"Date":"2026-07-23",'
              '"Customer":"Mazda","PartNo":"1","Line":"Line 1","Plan":300,'
              '"Output_10AM":30,"Output_LOR10AM":0.1,"Rejection_10AM":2,'
              '"Output_12PM":"","Output_LOR12PM":"","Rejection_12PM":"",'
              '"LastUpdated":"14:32"}}',
              200,
            );
          }),
        );

        final row = await service.fetchMachiningRow(
          customer: 'Mazda',
          part: '1',
          line: 'Line 1',
        );

        expect(requested.queryParameters, {
          'action': 'row',
          'module': 'machining',
          'customer': 'Mazda',
          'part': '1',
          'line': 'Line 1',
        });
        expect(row!.value('Plan'), '300');
        expect(row.value('Output_10AM'), '30');
        expect(row.lorLabel('Output_LOR10AM'), '10%');
        expect(row.value('Rejection_10AM'), '2');
        expect(row.value('Output_12PM'), isNull); // blank cell
        expect(row.value('Rejection_4PM'), isNull); // absent cell
      },
    );

    test('submit: posts secret + module + only the provided fields', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.submitMachiningUpdate({
        'Customer': 'Mazda',
        'PartNo': '1',
        'Line': 'Line 1',
        'Plan': '300',
        'Output_10AM': '30',
        'Rejection_10AM': '2',
      });

      expect(sent['secret'], 'hicom2026changeme');
      expect(sent['module'], 'machining');
      expect(sent['data'], {
        'Customer': 'Mazda',
        'PartNo': '1',
        'Line': 'Line 1',
        'Plan': '300',
        'Output_10AM': '30',
        'Rejection_10AM': '2',
      });
    });

    test('GET surfaces an explicit error envelope', () async {
      final service = SheetsService(
        client: MockClient(
          (request) async => http.Response(
            '{"status":"error","message":"Unknown customer"}',
            200,
          ),
        ),
      );

      await expectLater(
        service.fetchMachiningParts('Nobody'),
        throwsA(
          isA<SheetsSubmissionException>().having(
            (e) => e.message,
            'message',
            'Unknown customer',
          ),
        ),
      );
    });
  });

  group('config manage API', () {
    test(
      'fetchConfig: passes action+module, parses groups/parts/lines',
      () async {
        late Uri requested;
        final service = SheetsService(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response(
              '{"status":"success","data":{'
              '"groups":["Mazda","Proton"],'
              '"partsByGroup":{"Mazda":["1","2"],"Proton":["4"]},'
              '"lines":["Line 1","Line 2"]}}',
              200,
            );
          }),
        );

        final snapshot = await service.fetchConfig('machining');

        expect(requested.queryParameters, {
          'action': 'config',
          'module': 'machining',
        });
        expect(snapshot.groups, ['Mazda', 'Proton']);
        expect(snapshot.partsByGroup['Mazda'], ['1', '2']);
        expect(snapshot.partsByGroup['Proton'], ['4']);
        expect(snapshot.lines, ['Line 1', 'Line 2']);
      },
    );

    test(
      'fetchConfig: defaults to an empty line list for non-machining',
      () async {
        final service = SheetsService(
          client: MockClient(
            (request) async => http.Response(
              '{"status":"success","data":{'
              '"groups":["1212"],"partsByGroup":{"1212":["1"]}}}',
              200,
            ),
          ),
        );

        final snapshot = await service.fetchConfig('casting');

        expect(snapshot.lines, isEmpty);
      },
    );

    test('configAdd: posts op=add with group omitted when null', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.configAdd(module: 'casting', kind: 'group', value: '5151');

      expect(sent['secret'], 'hicom2026changeme');
      expect(sent['action'], 'config');
      expect(sent['op'], 'add');
      expect(sent['module'], 'casting');
      expect(sent['kind'], 'group');
      expect(sent.containsKey('group'), isFalse);
      expect(sent['value'], '5151');
      expect(sent.containsKey('newValue'), isFalse);
    });

    test('configAdd: includes group for kind=part', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.configAdd(
        module: 'casting',
        kind: 'part',
        group: '1212',
        value: '11',
      );

      expect(sent['group'], '1212');
      expect(sent['value'], '11');
    });

    test('configRename: posts op=rename with newValue', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.configRename(
        module: 'machining',
        kind: 'line',
        value: 'Line 1',
        newValue: 'Line 1B',
      );

      expect(sent['op'], 'rename');
      expect(sent['kind'], 'line');
      expect(sent['value'], 'Line 1');
      expect(sent['newValue'], 'Line 1B');
    });

    test('configDelete: posts op=delete', () async {
      late Map<String, dynamic> sent;
      final service = SheetsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"status":"success"}', 200);
        }),
      );

      await service.configDelete(
        module: 'secondary',
        kind: 'group',
        value: 'ST1',
      );

      expect(sent['op'], 'delete');
      expect(sent['kind'], 'group');
      expect(sent['value'], 'ST1');
    });

    test('config mutation surfaces a backend error envelope', () async {
      final service = SheetsService(
        client: MockClient(
          (request) async => http.Response(
            '{"status":"error","message":"Already exists"}',
            200,
          ),
        ),
      );

      await expectLater(
        service.configAdd(module: 'casting', kind: 'group', value: '1212'),
        throwsA(
          isA<SheetsSubmissionException>().having(
            (e) => e.message,
            'message',
            'Already exists',
          ),
        ),
      );
    });
  });
}
