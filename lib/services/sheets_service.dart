import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/analytics_models.dart';
import '../models/app_user.dart';
import '../models/casting_models.dart';
import '../models/config_models.dart';
import '../models/machining_models.dart';
import '../models/part_code.dart';
import '../models/raw_table.dart';
import '../models/rejection.dart';
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
/// selectors + shift-date:
///   GET  ?action=dashboard&module=X&shift=Z     -> top-level cards + last update
///   GET  ?action=parts&module=X&shift=Z&...     -> next-level cards
///   GET  ?action=row&module=X&shift=Z&...        -> this shift's saved row/null
///   POST { "secret": ..., "module": X, "data": { Shift, ...changed fields } }
///        -> backend upserts this shift's row and recalculates LOR%
///
/// Machining runs one level deeper (Operation -> Customer -> Part) since it
/// is keyed by Customer + PartNo + Operation instead of two selectors.
///
/// ALL THREE modules are now shift-aware: every dashboard/parts/row call takes
/// `shift` ("Day" | "Night") and submitted data must include a `Shift` field —
/// see casting_models.dart for why (real day/night schedule, not calendar
/// midnight). All three also carry an MO (manufacturing order) number per part
/// (see the config ops below).
///
/// A separate Config API manages the list of valid groups/parts
/// itself (add/delete/rename), backing the manage/settings screens:
///   GET  ?action=config&module=X -> { groups, partsByGroup, operations }
///   POST { secret, action: 'config', op: 'add'|'delete'|'rename', module,
///          kind: 'group'|'part'|'operation', group?, value, newValue? }
///   POST { secret, action: 'config', op: `<module>AddPart`/`<module>EditPart`
///          (casting|secondary|machining), group, part, newPart?, mo? } --
///          part rows in all three modules carry an MO number.
class SheetsService {
  SheetsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Who is signed in, set by the auth gate after login. Every module save
  /// carries it as UserEmail so the sheet records who logged which hour —
  /// and the backend refuses writes from deactivated accounts.
  static String? currentUserEmail;

  /// Generous because the backend is Apps Script: a warm call takes 2-3s, but
  /// a cold container can take far longer, and failing at 20s turned a slow
  /// answer into a false "no network" on the floor.
  static const Duration _timeout = Duration(seconds: 45);

  /// [data] plus the signed-in user's email — the attribution the backend
  /// stamps into LoggedBy/LogMeta.
  static Map<String, String> _attributed(Map<String, String> data) {
    final email = currentUserEmail;
    if (email == null || email.isEmpty) return data;
    return {...data, 'UserEmail': email};
  }

  // ---------- Users (login gate + registration) ----------

  /// The Users-tab profile for [email], or null when not registered yet.
  Future<AppUser?> fetchUserProfile(String email) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'user',
      'email': email,
    });
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];
    return data is Map<String, dynamic> ? AppUser.fromJson(data) : null;
  }

  /// One-time registration after the first Firebase sign-in. The backend
  /// appends to the Users tab with status "active" — and doubles as the
  /// repair path for a row that predates the Department column.
  Future<AppUser> registerUser({
    required String email,
    required String name,
    required String employeeId,
    required String department,
  }) async {
    final decoded = await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'user',
      'op': 'register',
      'email': email,
      'name': name,
      'employeeId': employeeId,
      'department': department,
    });
    // The backend decides the stored department (the admin is always "All"),
    // so prefer its answer over what was asked for.
    if (decoded is Map<String, dynamic> &&
        decoded['data'] is Map<String, dynamic>) {
      return AppUser.fromJson(decoded['data'] as Map<String, dynamic>);
    }
    return AppUser(
      email: email,
      name: name,
      employeeId: employeeId,
      department: department,
      status: 'active',
    );
  }

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
      'data': _attributed(data),
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
      'UserEmail': ?currentUserEmail,
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
      'UserEmail': ?currentUserEmail,
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
      'data': _attributed(data),
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
      'UserEmail': ?currentUserEmail,
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
      'UserEmail': ?currentUserEmail,
      'op': 'secondaryEditPart',
      'group': station,
      'part': part,
      'newPart': newPart,
      'mo': ?mo,
    });
  }

  // ---------- Machining incremental API (shift-aware: Day or Night) ----------

  /// Customers with anything logged against [operation] this shift. Every
  /// read below the operation picker is scoped to it — a part machined and
  /// then assembled is two independent rows.
  Future<List<CustomerStatus>> fetchMachiningDashboard({
    required String shift,
    required String operation,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'dashboard',
      'module': 'machining',
      'shift': shift,
      'operation': operation,
    });
    return _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(CustomerStatus.fromJson).toList();
  }

  Future<List<MachiningPartStatus>> fetchMachiningParts(
    String customer, {
    required String shift,
    required String operation,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'parts',
      'module': 'machining',
      'customer': customer,
      'shift': shift,
      'operation': operation,
    });
    return _asList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(MachiningPartStatus.fromJson)
        .toList();
  }

  /// This shift's saved row for this Customer + Part + Operation, or null.
  Future<MachiningRow?> fetchMachiningRow({
    required String customer,
    required String part,
    required String operation,
    required String shift,
  }) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'row',
      'module': 'machining',
      'customer': customer,
      'part': part,
      'operation': operation,
      'shift': shift,
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

  /// Saves a partial machining update. [data] must contain Customer, PartNo,
  /// Operation and Shift plus ONLY the fields the user filled/changed.
  Future<void> submitMachiningUpdate(Map<String, String> data) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'module': 'machining',
      'data': _attributed(data),
    });
  }

  /// Adds a new Machining part under [customer], optionally with its current
  /// MO (manufacturing order) number. MO is per-part — shared by both operations.
  Future<void> addMachiningPart({
    required String customer,
    required String part,
    String? mo,
  }) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'UserEmail': ?currentUserEmail,
      'op': 'machiningAddPart',
      'group': customer,
      'part': part,
      'mo': ?mo,
    });
  }

  /// Renames a Machining part and/or updates its MO number. Only ever touches
  /// the Config sheet — rows already logged keep the MO snapshotted onto them.
  Future<void> editMachiningPart({
    required String customer,
    required String part,
    required String newPart,
    String? mo,
  }) async {
    await _postJson(CASTING_WEBHOOK_URL, {
      'secret': SHEETS_SHARED_SECRET,
      'action': 'config',
      'UserEmail': ?currentUserEmail,
      'op': 'machiningEditPart',
      'group': customer,
      'part': part,
      'newPart': newPart,
      'mo': ?mo,
    });
  }

  // ---------- Parts master (imported CSV) ----------

  /// The distinct part codes available for [module], from the Parts master
  /// sheet filtered by Department. Feeds the add-part dropdown; picking a code
  /// tells the backend which barcode + name to snapshot onto the row.
  /// One production sheet tab, verbatim — the Tables screen's whole source.
  ///
  /// Not cached: the point of the screen is to show what the sheet holds
  /// right now, and a stale table is worse than a slow one.
  Future<RawTable> fetchRawTab(String tab, {int limit = 300}) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'rawtab',
      'name': tab,
      'limit': '$limit',
    });
    if (decoded is Map<String, dynamic>) {
      final inner = decoded['data'];
      if (inner is Map<String, dynamic>) return RawTable.fromJson(inner);
      return RawTable.fromJson(decoded);
    }
    throw const SheetsSubmissionException('Unexpected server response.');
  }

  Future<List<PartCode>> fetchPartCodes(String module) async {
    final cached = _partCodeCache[module];
    if (cached != null) return cached;

    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'partcodes',
      'module': module,
    });
    final codes = _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(PartCode.fromJson).toList();
    _partCodeCache[module] = codes;
    return codes;
  }

  /// The full rejection-code master (~230 defect types), for the Machining
  /// entry screen's defect picker. Cached like the parts master.
  Future<List<RejectionType>> fetchRejectionTypes() async {
    final cached = _rejectionTypeCache;
    if (cached != null) return cached;

    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'rejectiontypes',
    });
    final types = _asList(
      decoded,
    ).whereType<Map<String, dynamic>>().map(RejectionType.fromJson).toList();
    _rejectionTypeCache = types;
    return types;
  }

  /// The parts and rejection masters are imported CSVs that change rarely,
  /// while their pickers are opened constantly — so each is fetched once and
  /// reused for the rest of the session. Static because every screen builds
  /// its own [SheetsService]. (Re-imported a CSV? Restart the app.)
  static final Map<String, List<PartCode>> _partCodeCache = {};
  static List<RejectionType>? _rejectionTypeCache;

  @visibleForTesting
  static void clearMasterCaches() {
    _partCodeCache.clear();
    _rejectionTypeCache = null;
  }

  // ---------- Config: manage groups/parts/lines ----------

  /// The full set of groups (DCM/Station/Customer), their parts, and (for
  /// Machining) the global operation list — used by the manage/settings screens.
  Future<ConfigSnapshot> fetchConfig(String module) async {
    final decoded = await _getJson(CASTING_WEBHOOK_URL, {
      'action': 'config',
      'UserEmail': ?currentUserEmail,
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
  /// [group]) or a Machining operation ('kind'='operation', global).
  Future<void> configAdd({
    required String module,
    required String kind,
    String? group,
    required String value,
  }) => _configMutate('add', module, kind, group, value, null);

  /// Deletes a group (cascades to its parts), a part, or an operation.
  Future<void> configDelete({
    required String module,
    required String kind,
    String? group,
    required String value,
  }) => _configMutate('delete', module, kind, group, value, null);

  /// Renames a group (cascades to its parts' group reference), a part, or a
  /// operation. Only updates the Config sheet — historical production rows keep
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
      'UserEmail': ?currentUserEmail,
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
  /// [days] days, summed across every group/part/operation in the module.
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

  /// Returns the decoded JSON body when the script sent one, else null —
  /// registration reads its stored profile back out of it.
  Future<dynamic> _postJson(String url, Map<String, dynamic> payload) async {
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
        final decoded = jsonDecode(response.body);
        _throwIfErrorEnvelope(decoded);
        return decoded;
      } on FormatException {
        // Non-JSON body (e.g. redirect HTML) — treat as success.
      }
    }
    return null;
  }

  /// GET with query params, following the Apps Script redirect, returning
  /// the decoded JSON body (list, map or null).
  ///
  /// Apps Script normally answers in 2-3s, but a cold container occasionally
  /// stalls for far longer — which looked to the floor like "no internet" even
  /// though the network was fine. Reads are safe to repeat, so a timeout is
  /// retried once before giving up.
  Future<dynamic> _getJson(String url, Map<String, String> params) async {
    final uri = Uri.parse(url).replace(queryParameters: params);

    late final http.Response response;
    try {
      response = await _getWithRetry(uri);
    } on TimeoutException {
      throw const SheetsSubmissionException(
        'The sheet is taking too long to answer. Give it a moment and retry.',
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

  /// One retry on timeout only. A GET changes nothing, so repeating it is
  /// safe — unlike the upsert POST, which is never retried automatically.
  Future<http.Response> _getWithRetry(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      return await _client.get(uri).timeout(_timeout);
    }
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
