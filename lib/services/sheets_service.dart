import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../models/casting_models.dart';
import '../models/config_models.dart';
import '../models/machining_models.dart';
import '../models/secondary_models.dart';

/// Thrown when a request to the Sheets backend fails.
class SheetsSubmissionException implements Exception {
  const SheetsSubmissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client for the unified Apps Script Web App backend (CASTING_WEBHOOK_URL).
///
/// All three modules share one incremental upsert API, routed by a `module`
/// field ("casting" | "secondary" | "machining"), each keyed by their own
/// selectors + Date:
///   GET  ?action=dashboard&module=X             -> top-level cards + last update
///   GET  ?action=parts&module=X&...             -> next-level cards
///   GET  ?action=row&module=X&...                -> today's saved row or null
///   POST { "secret": ..., "module": X, "data": { ...only changed fields } }
///        -> backend upserts today's row and recalculates LOR%
///
/// Machining adds a `?action=lines` step (Customer -> Part -> Line) since it
/// is keyed by Customer + PartNo + Line + Date instead of two selectors.
///
/// Casting AND Secondary are shift-aware: every dashboard/parts/row call also
/// takes `shift` ("Day" | "Night"), and submitted data must include a `Shift`
/// field — see casting_models.dart / secondary_models.dart for why (real
/// day/night shift schedule, not calendar midnight). Both also carry an MO
/// (manufacturing order) number per part (see the config ops below).
/// Machining is unchanged (single sheet, no shift, no MO).
///
/// A separate Config API manages the list of valid groups/parts/lines
/// itself (add/delete/rename), backing the manage/settings screens:
///   GET  ?action=config&module=X -> { groups, partsByGroup, lines }
///   POST { secret, action: 'config', op: 'add'|'delete'|'rename', module,
///          kind: 'group'|'part'|'line', group?, value, newValue? }
///   POST { secret, action: 'config', op: `castingAddPart`/`castingEditPart`
///          or `secondaryAddPart`/`secondaryEditPart`, group, part, newPart?,
///          mo? } -- Casting/Secondary parts only, since they carry an MO.
class SheetsService {
  SheetsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  // ---------- Casting incremental API (shift-aware: Day or Night) ----------

  Future<List<DcmStatus>> fetchCastingDashboard({required String shift}) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'dashboard',
      'shift': shift,
    });
    return _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(DcmStatus.fromJson).toList();
  }

  Future<List<PartStatus>> fetchCastingParts(
    String dcm, {
    required String shift,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'parts',
      'dcm': dcm,
      'shift': shift,
    });
    return _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(PartStatus.fromJson).toList();
  }

  /// This shift's saved row for this DCM + Part, or null if none yet.
  Future<CastingRow?> fetchCastingRow({
    required String dcm,
    required String part,
    required String shift,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'row',
      'dcm': dcm,
      'part': part,
      'shift': shift,
    });
    if (decoded == null) return null;
    if (decoded is Map<String, dynamic>) {
      // Accept both a bare row and a {status, data} envelope.
      if (decoded.containsKey('data')) {
        final inner = decoded['data'];
        return inner is Map<String, dynamic> ? CastingRow(inner) : null;
      }
      return decoded.isEmpty ? null : CastingRow(decoded);
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  /// Saves a partial casting update. [data] must contain DCM, PartNo and
  /// Shift plus ONLY the fields the user filled/changed; the backend upserts
  /// this shift's row and recalculates LOR%.
  Future<void> submitCastingUpdate(Map<String, String> data) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'module': 'casting',
      'data': data,
    });
  }

  /// Adds a new Casting part under [dcm], optionally with its current MO
  /// (manufacturing order) number.
  Future<void> addCastingPart({
    required String dcm,
    required String part,
    String? mo,
  }) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'op': 'castingAddPart',
      'group': dcm,
      'part': part,
      'mo': ?mo,
    });
  }

  /// Renames a Casting part and/or updates its MO number. Only ever touches
  /// the Config sheet — rows already logged keep whatever MO was snapshotted
  /// onto them when they were created.
  Future<void> editCastingPart({
    required String dcm,
    required String part,
    required String newPart,
    String? mo,
  }) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'op': 'castingEditPart',
      'group': dcm,
      'part': part,
      'newPart': newPart,
      'mo': ?mo,
    });
  }

  // ---------- Secondary incremental API (shift-aware: Day or Night) ----------

  Future<List<StationStatus>> fetchSecondaryDashboard({
    required String shift,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'dashboard',
      'module': 'secondary',
      'shift': shift,
    });
    return _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(StationStatus.fromJson).toList();
  }

  Future<List<SecondaryPartStatus>> fetchSecondaryParts(
    String station, {
    required String shift,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'parts',
      'module': 'secondary',
      'station': station,
      'shift': shift,
    });
    return _asList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(SecondaryPartStatus.fromJson)
        .toList();
  }

  /// This shift's saved row for this Station + Part, or null if none yet.
  Future<SecondaryRow?> fetchSecondaryRow({
    required String station,
    required String part,
    required String shift,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'row',
      'module': 'secondary',
      'station': station,
      'part': part,
      'shift': shift,
    });
    if (decoded == null) return null;
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('data')) {
        final inner = decoded['data'];
        return inner is Map<String, dynamic> ? SecondaryRow(inner) : null;
      }
      return decoded.isEmpty ? null : SecondaryRow(decoded);
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  /// Saves a partial secondary update. [data] must contain Station, PartNo and
  /// Shift plus ONLY the fields the user filled/changed; the backend upserts
  /// this shift's row and recalculates LOR%.
  Future<void> submitSecondaryUpdate(Map<String, String> data) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'module': 'secondary',
      'data': data,
    });
  }

  /// Adds a new Secondary part under [station], optionally with its current MO
  /// (manufacturing order) number.
  Future<void> addSecondaryPart({
    required String station,
    required String part,
    String? mo,
  }) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'op': 'secondaryAddPart',
      'group': station,
      'part': part,
      'mo': ?mo,
    });
  }

  /// Renames a Secondary part and/or updates its MO number. Only ever touches
  /// the Config sheet — rows already logged keep whatever MO was snapshotted
  /// onto them when they were created.
  Future<void> editSecondaryPart({
    required String station,
    required String part,
    required String newPart,
    String? mo,
  }) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'op': 'secondaryEditPart',
      'group': station,
      'part': part,
      'newPart': newPart,
      'mo': ?mo,
    });
  }

  // ---------- Machining incremental API ----------

  Future<List<CustomerStatus>> fetchMachiningDashboard() async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'dashboard',
      'module': 'machining',
    });
    return _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(CustomerStatus.fromJson).toList();
  }

  Future<List<MachiningPartStatus>> fetchMachiningParts(String customer) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'parts',
      'module': 'machining',
      'customer': customer,
    });
    return _asList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(MachiningPartStatus.fromJson)
        .toList();
  }

  Future<List<MachiningLineStatus>> fetchMachiningLines({
    required String customer,
    required String part,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'lines',
      'module': 'machining',
      'customer': customer,
      'part': part,
    });
    return _asList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(MachiningLineStatus.fromJson)
        .toList();
  }

  /// Today's saved row for this Customer + Part + Line, or null if none yet.
  Future<MachiningRow?> fetchMachiningRow({
    required String customer,
    required String part,
    required String line,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'row',
      'module': 'machining',
      'customer': customer,
      'part': part,
      'line': line,
    });
    if (decoded == null) return null;
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('data')) {
        final inner = decoded['data'];
        return inner is Map<String, dynamic> ? MachiningRow(inner) : null;
      }
      return decoded.isEmpty ? null : MachiningRow(decoded);
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  /// Saves a partial machining update. [data] must contain Customer, PartNo
  /// and Line plus ONLY the fields the user filled/changed.
  Future<void> submitMachiningUpdate(Map<String, String> data) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'module': 'machining',
      'data': data,
    });
  }

  // ---------- Config: manage groups/parts/lines ----------

  /// The full set of groups (DCM/Station/Customer), their parts, and (for
  /// Machining) the global line list — used by the manage/settings screens.
  Future<ConfigSnapshot> fetchConfig(String module) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'config',
      'module': module,
    });
    if (decoded is Map<String, dynamic> && decoded['data'] is Map) {
      return ConfigSnapshot.fromJson(
        (decoded['data'] as Map).cast<String, dynamic>(),
      );
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  /// Adds a group ('group', no [group] parent), a part ('part', requires
  /// [group]) or a Machining line ('kind'='line', global).
  Future<void> configAdd({
    required String module,
    required String kind,
    String? group,
    required String value,
  }) => _configMutate('add', module, kind, group, value, null);

  /// Deletes a group (cascades to its parts), a part, or a line.
  Future<void> configDelete({
    required String module,
    required String kind,
    String? group,
    required String value,
  }) => _configMutate('delete', module, kind, group, value, null);

  /// Renames a group (cascades to its parts' group reference), a part, or a
  /// line. Only updates the Config sheet — historical production rows keep
  /// whatever name was in effect when they were logged.
  Future<void> configRename({
    required String module,
    required String kind,
    String? group,
    required String value,
    required String newValue,
  }) => _configMutate('rename', module, kind, group, value, newValue);

  Future<void> _configMutate(
    String op,
    String module,
    String kind,
    String? group,
    String value,
    String? newValue,
  ) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'op': op,
      'module': module,
      'kind': kind,
      'group': ?group,
      'value': value,
      'newValue': ?newValue,
    });
  }

  // ---------- Analytics: daily trend totals for the Dashboard tab ----------

  /// Daily output/LOR% (and, for Machining, rejection) totals for the last
  /// [days] days, summed across every group/part/line in the module.
  Future<AnalyticsSeries> fetchAnalytics({
    required String module,
    int days = 14,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'analytics',
      'module': module,
      'days': '$days',
    });
    if (decoded is Map<String, dynamic> && decoded['data'] is Map) {
      return AnalyticsSeries.fromJson(
        (decoded['data'] as Map).cast<String, dynamic>(),
      );
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  // ---------- Shared HTTP plumbing ----------

  Future<void> _postJson(String url, Map<String, dynamic> payload) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            // text/plain keeps this a CORS "simple request" so it also works
            // from Flutter web — Apps Script cannot answer the OPTIONS
            // preflight that application/json would trigger. The script
            // still reads the JSON from e.postData.contents.
            headers: {'Content-Type': 'text/plain; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const SheetsSubmissionException(
        'Connection timed out. Check the network and try again.',
      );
    } on http.ClientException {
      // Covers socket/network failures on mobile, desktop and web.
      throw const SheetsSubmissionException(
        'No connection. Check Wi-Fi / mobile data and try again.',
      );
    }

    // Apps Script Web Apps reply 302 (redirect) on success when called
    // directly, so treat any non-error status as delivered.
    if (response.statusCode >= 400) {
      throw SheetsSubmissionException(
        'Server error (${response.statusCode}). Please try again.',
      );
    }

    // If the script returned a JSON body (status 200), honour an explicit
    // failure result such as {"status": "error", "message": "..."}.
    if (response.statusCode == 200 && response.body.isNotEmpty) {
      try {
        _throwIfErrorEnvelope(jsonDecode(response.body));
      } on FormatException {
        // Non-JSON body (e.g. redirect HTML) — treat as success.
      }
    }
  }

  /// GET with query params, following the Apps Script redirect, returning
  /// the decoded JSON body (list, map or null).
  Future<dynamic> _getJson(String url, Map<String, String> params) async {
    final uri = Uri.parse(url).replace(queryParameters: params);

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const SheetsSubmissionException(
        'Connection timed out. Check the network and try again.',
      );
    } on http.ClientException {
      throw const SheetsSubmissionException(
        'No connection. Check Wi-Fi / mobile data and try again.',
      );
    }

    if (response.statusCode >= 400) {
      throw SheetsSubmissionException(
        'Server error (${response.statusCode}). Please try again.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const SheetsSubmissionException('Unexpected server response.');
    }
    _throwIfErrorEnvelope(decoded);
    return decoded;
  }

  void _throwIfErrorEnvelope(dynamic decoded) {
    if (decoded is Map<String, dynamic> && decoded['status'] == 'error') {
      final message = decoded['message'];
      throw SheetsSubmissionException(
        message is String && message.isNotEmpty
            ? message
            : 'The server rejected the request.',
      );
    }
  }

  /// Accepts a bare JSON list or a {status, data: [...]} envelope.
  List<dynamic> _asList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      return decoded['data'] as List;
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  void dispose() => _client.close();
}
