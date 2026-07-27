/**
 * HICOM Production Log — Apps Script reference.
 *
 * Unified incremental upsert backend for Casting, Secondary, and Machining.
 * Casting/Secondary are keyed by (DCM|Station) + Part + Date. Machining adds
 * a third selector, Line, so it is keyed by Customer + Part + Line + Date.
 *
 * The list of valid DCMs/Stations/Customers/Parts/Lines is no longer
 * hardcoded — it lives in a "Config" sheet tab so supervisors can add/edit/
 * delete them from the app (Settings/manage screens) without a redeploy.
 *
 * === REQUIRED: Sheet header rows (row 1), spelled EXACTLY like this ===
 *
 * Config (drives every dropdown/card list across all 3 modules):
 *   Module | Kind | Group | Value | MO
 *   - Kind = "group": one row per DCM/Station/Customer. Group = its name,
 *     Value blank. (Lets a group exist with zero parts yet.)
 *   - Kind = "part": one row per part under a group. Group = the parent
 *     DCM/Station/Customer name, Value = the part name.
 *   - Kind = "line": Machining only, global (not per-part). Group blank,
 *     Value = the line name (e.g. "Line 1").
 *   Module is stored lowercase ("casting" | "secondary" | "machining").
 *   MO (Casting parts only — see getConfigPartMo): the part's current
 *     manufacturing order number, editable from the app; blank/unused for
 *     every other row. Added by migrateCastingShiftSchema(), see below.
 *   Run seedDefaultConfig() once from the Apps Script editor (Run menu)
 *   after creating this tab to populate it with the current defaults.
 *
 * Casting (shift-split — the only module with this schema. Each shift is its
 * OWN sheet tab so rows are never half-empty and there is no Shift column;
 * the tab a row lives in IS its shift. Run setupCastingShiftSheets() once to
 * create both tabs. Keyed by DCM+PartNo+shift-date within each sheet):
 *
 *   Casting_Day (Day shift, checkpoints 8AM-6PM):
 *     Date | DCM | PartNo | MO | Plan |
 *     Output_8AM  | Output_LOR8AM  | Output_10AM | Output_LOR10AM |
 *     Output_12PM | Output_LOR12PM | Output_2PM  | Output_LOR2PM  |
 *     Output_4PM  | Output_LOR4PM  | Output_6PM  | Output_LOR6PM  | LastUpdated
 *
 *   Casting_Night (Night shift, checkpoints 8PM-6AM crossing midnight —
 *   post-midnight checkpoints file under the date the shift STARTED, see
 *   getShiftDate):
 *     Date | DCM | PartNo | MO | Plan |
 *     Output_8PM  | Output_LOR8PM  | Output_10PM | Output_LOR10PM |
 *     Output_12AM | Output_LOR12AM | Output_2AM  | Output_LOR2AM  |
 *     Output_4AM  | Output_LOR4AM  | Output_6AM  | Output_LOR6AM  | LastUpdated
 *
 *   - MO = manufacturing order number, snapshotted from the part's Config
 *     MO onto the row once, at creation — never rewritten by later Config
 *     edits, so historical rows keep whatever MO was active when logged.
 *   - Combined daily totals (Dashboard analytics) sum both sheets by Date.
 *
 * Secondary (shift-split like Casting — two tabs, keyed by Station+PartNo+
 * shift-date, Actual_/LOR_ prefixes, MO number per part. Run
 * setupSecondaryShiftSheets() once):
 *
 *   Secondary_Day (Day shift, checkpoints 8AM-6PM):
 *     Date | Station | PartNo | MO | Plan |
 *     Actual_8AM  | LOR_8AM  | Actual_10AM | LOR_10AM |
 *     Actual_12PM | LOR_12PM | Actual_2PM  | LOR_2PM  |
 *     Actual_4PM  | LOR_4PM  | Actual_6PM  | LOR_6PM  | LastUpdated
 *
 *   Secondary_Night (Night shift, checkpoints 8PM-6AM crossing midnight):
 *     Date | Station | PartNo | MO | Plan |
 *     Actual_8PM  | LOR_8PM  | Actual_10PM | LOR_10PM |
 *     Actual_12AM | LOR_12AM | Actual_2AM  | LOR_2AM  |
 *     Actual_4AM  | LOR_4AM  | Actual_6AM  | LOR_6AM  | LastUpdated
 *
 * Machining:
 *   Date | Customer | PartNo | Line | Plan |
 *   Output_10AM | Output_LOR10AM | Rejection_10AM |
 *   Output_12PM | Output_LOR12PM | Rejection_12PM |
 *   Output_2PM  | Output_LOR2PM  | Rejection_2PM  |
 *   Output_4PM  | Output_LOR4PM  | Rejection_4PM  |
 *   Output_6PM  | Output_LOR6PM  | Rejection_6PM  |
 *   Output_8PM  | Output_LOR8PM  | Rejection_8PM  | LastUpdated
 *
 * After editing: Deploy > New deployment (editing an existing deployment's
 * version has not reliably gone live in testing — always cut a new one).
 */

var SECRET_KEY = 'hicom2026changeme';
var MACHINING_SHEET = 'Machining';
var CONFIG_SHEET = 'Config';
var OUTPUT_TIME_SLOTS = ['10AM', '12PM', '2PM', '4PM', '6PM', '8PM'];

// Casting AND Secondary: real 2-shift schedule. Day checkpoints run 8AM-6PM;
// Night checkpoints run 8PM-6AM (crossing midnight). Machining is unchanged
// and still uses the single OUTPUT_TIME_SLOTS list above.
//
// Each shift is its OWN sheet tab (Casting_Day/Casting_Night,
// Secondary_Day/Secondary_Night) so every row holds only its shift's six
// checkpoints — no half-empty rows, and no Shift column (the tab the row
// lives in IS the shift). Casting uses Output_/Output_LOR column prefixes;
// Secondary uses Actual_/LOR_ — the slot TIMES are identical.
var CASTING_DAY_SHEET = 'Casting_Day';
var CASTING_NIGHT_SHEET = 'Casting_Night';
var SECONDARY_DAY_SHEET = 'Secondary_Day';
var SECONDARY_NIGHT_SHEET = 'Secondary_Night';
var DAY_SLOTS = ['8AM', '10AM', '12PM', '2PM', '4PM', '6PM'];
var NIGHT_SLOTS = ['8PM', '10PM', '12AM', '2AM', '4AM', '6AM'];
// Back-compat aliases (Casting code referred to these names).
var CASTING_DAY_SLOTS = DAY_SLOTS;
var CASTING_NIGHT_SLOTS = NIGHT_SLOTS;

function slotsForShift(shift) {
  return shift === 'Night' ? NIGHT_SLOTS : DAY_SLOTS;
}
// Alias kept so existing Casting call sites read naturally.
function castingSlotsForShift(shift) {
  return slotsForShift(shift);
}

// The sheet tab a Casting row lives in, chosen purely by shift. This replaces
// the old single 'Casting' sheet + Shift column.
function getCastingSheetForShift(shift) {
  var name = shift === 'Night' ? CASTING_NIGHT_SHEET : CASTING_DAY_SHEET;
  return requireSheet(name, 'setupCastingShiftSheets');
}

// The sheet tab a Secondary row lives in, chosen purely by shift.
function getSecondarySheetForShift(shift) {
  var name = shift === 'Night' ? SECONDARY_NIGHT_SHEET : SECONDARY_DAY_SHEET;
  return requireSheet(name, 'setupSecondaryShiftSheets');
}

// Header frame for a Casting shift sheet, built from that shift's slots.
function castingHeadersForShift(shift) {
  var headers = ['Date', 'DCM', 'PartNo', 'MO', 'Plan'];
  slotsForShift(shift).forEach(function (slot) {
    headers.push('Output_' + slot);
    headers.push('Output_LOR' + slot);
  });
  headers.push('LastUpdated');
  return headers;
}

// Header frame for a Secondary shift sheet — same shape as Casting but keyed
// by Station and using the Actual_/LOR_ column prefixes.
function secondaryHeadersForShift(shift) {
  var headers = ['Date', 'Station', 'PartNo', 'MO', 'Plan'];
  slotsForShift(shift).forEach(function (slot) {
    headers.push('Actual_' + slot);
    headers.push('LOR_' + slot);
  });
  headers.push('LastUpdated');
  return headers;
}

// The "business date" a shift row belongs to. Day shift never crosses
// midnight, so it's always today. Night shift starts in the evening and
// runs past midnight — its early-morning checkpoints (12AM/2AM/4AM/6AM)
// must still be filed under the date the shift STARTED (yesterday evening),
// not the calendar day they happen to be typed in on. Shared by Casting and
// Secondary (both run the same 2-shift schedule).
function getShiftDate(shift) {
  var tz = Session.getScriptTimeZone();
  var now = new Date();
  if (shift === 'Night') {
    var hour = parseInt(Utilities.formatDate(now, tz, 'H'), 10);
    if (hour < 8) {
      var yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      return Utilities.formatDate(yesterday, tz, 'yyyy-MM-dd');
    }
  }
  return Utilities.formatDate(now, tz, 'yyyy-MM-dd');
}

// Bump this whenever you redeploy so you can confirm the new code went live:
// open the /exec URL in a browser and check the "version" field.
var BACKEND_VERSION = 'SECONDARY-2SHEET-v3';

function doGet(e) {
  try {
    var action = e && e.parameter ? e.parameter.action : null;
    var module = e && e.parameter ? e.parameter.module : null;

    if (action === 'config') return jsonResponse(getConfigSnapshot(module));
    if (action === 'analytics') return jsonResponse(getAnalytics(module, e.parameter.days));

    if (module === 'machining') {
      if (action === 'dashboard') return jsonResponse(getMachiningDashboard());
      if (action === 'parts') return jsonResponse(getMachiningParts(e.parameter.customer));
      if (action === 'lines') return jsonResponse(getMachiningLines(e.parameter.customer, e.parameter.part));
      if (action === 'row') {
        return jsonResponse(getMachiningRow(e.parameter.customer, e.parameter.part, e.parameter.line));
      }
    } else if (module === 'secondary') {
      // Secondary is now shift-aware too (Secondary_Day/Secondary_Night),
      // mirroring Casting — every call carries a shift.
      var sShift = e.parameter.shift;
      if (action === 'dashboard') return jsonResponse(getSecondaryDashboard(sShift));
      if (action === 'parts') return jsonResponse(getSecondaryParts(e.parameter.station, sShift));
      if (action === 'row') {
        return jsonResponse(getSecondaryRow(e.parameter.station, e.parameter.part, sShift));
      }
    } else {
      // Default / casting: its own dedicated shift-aware functions.
      var shift = e.parameter.shift;
      if (action === 'dashboard') return jsonResponse(getCastingDashboard(shift));
      if (action === 'parts') return jsonResponse(getCastingParts(e.parameter.dcm, shift));
      if (action === 'row') {
        return jsonResponse(getCastingRow(e.parameter.dcm, e.parameter.part, shift));
      }
    }

    return jsonResponse({
      status: 'ok',
      version: BACKEND_VERSION,
      message: 'HICOM logging backend running.',
    });
  } catch (err) {
    return jsonResponse({ status: 'error', message: err.toString() });
  }
}

function doPost(e) {
  try {
    var payload = JSON.parse(e.postData.contents);
    if (payload.secret !== SECRET_KEY) {
      return jsonResponse({ status: 'error', message: 'Unauthorized' });
    }
    if (payload.action === 'config') {
      // Casting/Secondary part ops that also carry an MO number — everything
      // else (groups, lines, Machining parts) stays on the generic
      // configMutate, untouched.
      if (payload.op === 'castingAddPart') return jsonResponse(addPartWithMo('casting', payload));
      if (payload.op === 'castingEditPart') return jsonResponse(editPartWithMo('casting', payload));
      if (payload.op === 'secondaryAddPart') return jsonResponse(addPartWithMo('secondary', payload));
      if (payload.op === 'secondaryEditPart') return jsonResponse(editPartWithMo('secondary', payload));
      return jsonResponse(configMutate(payload));
    }
    if (payload.module === 'casting') return jsonResponse(upsertCastingRow(payload.data));
    if (payload.module === 'secondary') return jsonResponse(upsertSecondaryRow(payload.data));
    if (payload.module === 'machining') return jsonResponse(upsertMachiningRow(payload.data));
    return jsonResponse({ status: 'error', message: 'Unknown module' });
  } catch (err) {
    return jsonResponse({ status: 'error', message: err.toString() });
  }
}

// ---------- Secondary: reads (shift-aware — Day/Night, separate sheets) -----
//
// Mirror of the Casting reads: keyed by Station + PartNo + shift-date within
// a per-shift sheet (Secondary_Day/Secondary_Night). Column prefixes are
// Actual_/LOR_ instead of Casting's Output_/Output_LOR.

function getSecondaryDashboard(shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getSecondarySheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var groups = getConfigGroups('secondary');
  var result = groups.map(function (station) {
    var match = rows.find(function (r) {
      return String(r.Station) === station && formatDateOnly(r.Date) === shiftDate;
    });
    // Key stays `dcm` in the JSON so StationStatus.fromJson (which reads
    // json['dcm']) is unchanged — the app maps it to `station`.
    return { dcm: station, lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null };
  });
  return { status: 'success', data: result };
}

function getSecondaryParts(station, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getSecondarySheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var slots = slotsForShift(shift);
  var parts = getConfigParts('secondary', station);
  var result = parts.map(function (part) {
    var match = rows.find(function (r) {
      return String(r.Station) === station && String(r.PartNo) === part &&
        formatDateOnly(r.Date) === shiftDate;
    });
    var filled = 0;
    if (match) {
      slots.forEach(function (slot) {
        var v = match['Actual_' + slot];
        if (v !== '' && v !== null && v !== undefined) filled++;
      });
    }
    return {
      part: part,
      mo: getConfigPartMo('secondary', station, part),
      lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null,
      fillPercent: match ? Math.round((filled / slots.length) * 100) : 0,
    };
  });
  return { status: 'success', data: result };
}

function getSecondaryRow(station, part, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getSecondarySheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var match = rows.find(function (r) {
    return String(r.Station) === station && String(r.PartNo) === part &&
      formatDateOnly(r.Date) === shiftDate;
  });
  if (!match) return { status: 'success', data: null };
  delete match._rowNum;
  return { status: 'success', data: match };
}

// ---------- Secondary: upsert (per-shift sheet, snapshots MO once) ----------

function upsertSecondaryRow(data) {
  // `data.Shift` is sent by the app only to pick the sheet — never stored.
  var shift = data.Shift === 'Night' ? 'Night' : 'Day';
  var sheet = getSecondarySheetForShift(shift);
  var headers = getHeaders(sheet);
  var rows = getAllRowsAsObjects(sheet);
  var shiftDate = getShiftDate(shift);
  var slots = slotsForShift(shift);

  var existing = rows.find(function (r) {
    return String(r.Station) === String(data.Station) &&
      String(r.PartNo) === String(data.PartNo) &&
      formatDateOnly(r.Date) === shiftDate;
  });

  var merged = existing ? Object.assign({}, existing) : {};
  merged.Date = shiftDate;
  merged.Station = data.Station;
  merged.PartNo = data.PartNo;
  if (!existing) {
    // Snapshot the part's currently-configured MO onto the row once, at
    // creation — later Config MO edits never rewrite already-logged rows.
    merged.MO = getConfigPartMo('secondary', data.Station, data.PartNo);
  }
  if (data.Plan !== undefined && data.Plan !== '') merged.Plan = data.Plan;

  slots.forEach(function (slot) {
    var outKey = 'Actual_' + slot;
    var lorKey = 'LOR_' + slot;
    if (data[outKey] !== undefined && data[outKey] !== '') {
      merged[outKey] = data[outKey];
      var plan = parseFloat(merged.Plan);
      var output = parseFloat(data[outKey]);
      if (plan > 0 && !isNaN(output)) {
        merged[lorKey] = Math.round((output / plan) * 100) + '%';
      }
    }
  });

  merged.LastUpdated = new Date();
  var rowArray = headers.map(function (h) {
    return merged.hasOwnProperty(h) ? merged[h] : '';
  });

  if (existing) {
    sheet.getRange(existing._rowNum, 1, 1, headers.length).setValues([rowArray]);
  } else {
    sheet.appendRow(rowArray);
  }
  return {
    status: 'success',
    version: BACKEND_VERSION,
    message: existing ? 'Row updated (same row)' : 'Row created',
  };
}

// ---------- Casting: reads (shift-aware — Day/Night, separate sheets) -------
//
// Casting is keyed by DCM + PartNo + shift-date (see getShiftDate above)
// within a per-shift sheet, NOT plain calendar date like Machining. Each
// shift lives in its own tab (Casting_Day/Casting_Night), so a Day row and a
// Night row for the same DCM+Part+date never collide.

function getCastingDashboard(shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getCastingSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var groups = getConfigGroups('casting');
  var result = groups.map(function (dcm) {
    var match = rows.find(function (r) {
      return String(r.DCM) === dcm && formatDateOnly(r.Date) === shiftDate;
    });
    return { dcm: dcm, lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null };
  });
  return { status: 'success', data: result };
}

function getCastingParts(dcm, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getCastingSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var slots = castingSlotsForShift(shift);
  var parts = getConfigParts('casting', dcm);
  var result = parts.map(function (part) {
    var match = rows.find(function (r) {
      return String(r.DCM) === dcm && String(r.PartNo) === part &&
        formatDateOnly(r.Date) === shiftDate;
    });
    var filled = 0;
    if (match) {
      slots.forEach(function (slot) {
        var v = match['Output_' + slot];
        if (v !== '' && v !== null && v !== undefined) filled++;
      });
    }
    return {
      part: part,
      mo: getConfigPartMo('casting', dcm, part),
      lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null,
      fillPercent: match ? Math.round((filled / slots.length) * 100) : 0,
    };
  });
  return { status: 'success', data: result };
}

function getCastingRow(dcm, part, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getCastingSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var match = rows.find(function (r) {
    return String(r.DCM) === dcm && String(r.PartNo) === part &&
      formatDateOnly(r.Date) === shiftDate;
  });
  if (!match) return { status: 'success', data: null };
  delete match._rowNum;
  return { status: 'success', data: match };
}

// ---------- Casting: upsert (per-shift sheet, snapshots MO once at creation) ----------

function upsertCastingRow(data) {
  // `data.Shift` is sent by the app only to pick the sheet — it is NOT stored
  // as a column (the sheet tab already encodes the shift).
  var shift = data.Shift === 'Night' ? 'Night' : 'Day';
  var sheet = getCastingSheetForShift(shift);
  var headers = getHeaders(sheet);
  var rows = getAllRowsAsObjects(sheet);
  var shiftDate = getShiftDate(shift);
  var slots = castingSlotsForShift(shift);

  var existing = rows.find(function (r) {
    return String(r.DCM) === String(data.DCM) && String(r.PartNo) === String(data.PartNo) &&
      formatDateOnly(r.Date) === shiftDate;
  });

  var merged = existing ? Object.assign({}, existing) : {};
  merged.Date = shiftDate;
  merged.DCM = data.DCM;
  merged.PartNo = data.PartNo;
  if (!existing) {
    // Snapshot the part's CURRENTLY configured MO onto the row exactly once,
    // at creation. If the Config MO changes later (new month), rows already
    // logged keep the MO that was active when they were written — a later
    // Config edit must never silently rewrite already-logged history.
    merged.MO = getConfigPartMo('casting', data.DCM, data.PartNo);
  }
  if (data.Plan !== undefined && data.Plan !== '') merged.Plan = data.Plan;

  slots.forEach(function (slot) {
    var outKey = 'Output_' + slot;
    var lorKey = 'Output_LOR' + slot;
    if (data[outKey] !== undefined && data[outKey] !== '') {
      merged[outKey] = data[outKey];
      var plan = parseFloat(merged.Plan);
      var output = parseFloat(data[outKey]);
      if (plan > 0 && !isNaN(output)) {
        merged[lorKey] = Math.round((output / plan) * 100) + '%';
      }
    }
  });

  merged.LastUpdated = new Date();
  var rowArray = headers.map(function (h) {
    return merged.hasOwnProperty(h) ? merged[h] : '';
  });

  if (existing) {
    sheet.getRange(existing._rowNum, 1, 1, headers.length).setValues([rowArray]);
  } else {
    sheet.appendRow(rowArray);
  }
  return {
    status: 'success',
    version: BACKEND_VERSION,
    message: existing ? 'Row updated (same row)' : 'Row created',
  };
}

// ---------- Casting: part MO number (Config-sheet 5th column) ----------
//
// MO is scoped to (Casting, DCM, Part) — the same granularity as the part
// record itself — and lives on that part's Config row, NOT on every data
// row. upsertCastingRow snapshots it onto a new data row at creation time;
// editing it here only changes what NEW rows will pick up going forward.

function getConfigPartMo(module, group, part) {
  var rows = getConfigRows();
  var match = rows.find(function (r) {
    return String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
      String(r.Group) === group && String(r.Value) === part;
  });
  return match && match.MO ? String(match.MO) : '';
}

// Shared by Casting (group=DCM) and Secondary (group=Station) — the only two
// modules whose parts carry an MO number. `module` decides which Config rows
// are matched/written; the wire ops are castingAddPart/secondaryAddPart etc.
function addPartWithMo(module, payload) {
  var group = String(payload.group || '');
  var part = String(payload.part || '').trim();
  var mo = payload.mo !== undefined && payload.mo !== null ? String(payload.mo) : '';
  if (!group || !part) return { status: 'error', message: 'group and part are required' };

  var sheet = getConfigSheet();
  var rows = getAllRowsAsObjects(sheet);
  var dup = rows.some(function (r) {
    return String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
      String(r.Group) === group && String(r.Value) === part;
  });
  if (dup) return { status: 'error', message: 'Already exists' };
  sheet.appendRow([module, 'part', group, part, mo]);
  return { status: 'success', version: BACKEND_VERSION, message: 'Added' };
}

function editPartWithMo(module, payload) {
  var group = String(payload.group || '');
  var part = String(payload.part || '');
  var newPart = payload.newPart !== undefined && payload.newPart !== null ? String(payload.newPart).trim() : part;
  // null (not just empty string) means "leave MO unchanged".
  var mo = payload.mo !== undefined && payload.mo !== null ? String(payload.mo) : null;
  if (!group || !part || !newPart) {
    return { status: 'error', message: 'group, part and newPart are required' };
  }

  var sheet = getConfigSheet();
  var headers = getHeaders(sheet);
  var valueCol = headers.indexOf('Value') + 1;
  var moCol = headers.indexOf('MO') + 1;
  var rows = getAllRowsAsObjects(sheet);
  var match = rows.find(function (r) {
    return String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
      String(r.Group) === group && String(r.Value) === part;
  });
  if (!match) return { status: 'error', message: 'Not found' };
  if (newPart !== part) sheet.getRange(match._rowNum, valueCol).setValue(newPart);
  if (mo !== null && moCol > 0) sheet.getRange(match._rowNum, moCol).setValue(mo);
  return { status: 'success', version: BACKEND_VERSION, message: 'Updated' };
}

// ---------- Machining: reads (Customer -> Part -> Line -> entry) ----------

function getMachiningDashboard() {
  var rows = getAllRowsAsObjects(getModuleSheet('machining'));
  var today = getTodayString();
  var customers = getConfigGroups('machining');
  var result = customers.map(function (customer) {
    var latest = null;
    rows.forEach(function (r) {
      if (String(r.Customer) === customer && formatDateOnly(r.Date) === today && r.LastUpdated) {
        if (!latest || new Date(r.LastUpdated) > new Date(latest)) latest = r.LastUpdated;
      }
    });
    return { dcm: customer, lastUpdated: latest ? hhmm(latest) : null };
  });
  return { status: 'success', data: result };
}

function getMachiningParts(customer) {
  var rows = getAllRowsAsObjects(getModuleSheet('machining'));
  var today = getTodayString();
  var parts = getConfigParts('machining', customer);
  var result = parts.map(function (part) {
    var latest = null;
    rows.forEach(function (r) {
      if (String(r.Customer) === customer && String(r.PartNo) === part &&
          formatDateOnly(r.Date) === today && r.LastUpdated) {
        if (!latest || new Date(r.LastUpdated) > new Date(latest)) latest = r.LastUpdated;
      }
    });
    return { part: part, lastUpdated: latest ? hhmm(latest) : null };
  });
  return { status: 'success', data: result };
}

function getMachiningLines(customer, part) {
  var rows = getAllRowsAsObjects(getModuleSheet('machining'));
  var today = getTodayString();
  var lines = getConfigLines();
  var result = lines.map(function (line) {
    var match = rows.find(function (r) {
      return String(r.Customer) === customer && String(r.PartNo) === part &&
        String(r.Line) === line && formatDateOnly(r.Date) === today;
    });
    var filled = 0;
    if (match) {
      OUTPUT_TIME_SLOTS.forEach(function (slot) {
        var v = match['Output_' + slot];
        if (v !== '' && v !== null && v !== undefined) filled++;
      });
    }
    return {
      part: line,
      lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null,
      fillPercent: match ? Math.round((filled / OUTPUT_TIME_SLOTS.length) * 100) : 0,
    };
  });
  return { status: 'success', data: result };
}

function getMachiningRow(customer, part, line) {
  var rows = getAllRowsAsObjects(getModuleSheet('machining'));
  var today = getTodayString();
  var match = rows.find(function (r) {
    return String(r.Customer) === customer && String(r.PartNo) === part &&
      String(r.Line) === line && formatDateOnly(r.Date) === today;
  });
  if (!match) return { status: 'success', data: null };
  delete match._rowNum;
  return { status: 'success', data: match };
}

// ---------- Machining: upsert (partial merge, adds Rejection per slot) ----------

function upsertMachiningRow(data) {
  var sheet = getModuleSheet('machining');
  var headers = getHeaders(sheet);
  var rows = getAllRowsAsObjects(sheet);
  var today = getTodayString();

  var existing = rows.find(function (r) {
    return String(r.Customer) === String(data.Customer) &&
      String(r.PartNo) === String(data.PartNo) &&
      String(r.Line) === String(data.Line) &&
      formatDateOnly(r.Date) === today;
  });

  var merged = existing ? Object.assign({}, existing) : {};
  merged.Date = today;
  merged.Customer = data.Customer;
  merged.PartNo = data.PartNo;
  merged.Line = data.Line;
  if (data.Plan !== undefined && data.Plan !== '') merged.Plan = data.Plan;

  OUTPUT_TIME_SLOTS.forEach(function (slot) {
    var outKey = 'Output_' + slot;
    var lorKey = 'Output_LOR' + slot;
    var rejKey = 'Rejection_' + slot;
    if (data[outKey] !== undefined && data[outKey] !== '') {
      merged[outKey] = data[outKey];
      var plan = parseFloat(merged.Plan);
      var output = parseFloat(data[outKey]);
      if (plan > 0 && !isNaN(output)) {
        merged[lorKey] = Math.round((output / plan) * 100) + '%';
      }
    }
    if (data[rejKey] !== undefined && data[rejKey] !== '') {
      merged[rejKey] = data[rejKey];
    }
  });

  merged.LastUpdated = new Date();
  var rowArray = headers.map(function (h) {
    return merged.hasOwnProperty(h) ? merged[h] : '';
  });

  if (existing) {
    sheet.getRange(existing._rowNum, 1, 1, headers.length).setValues([rowArray]);
  } else {
    sheet.appendRow(rowArray);
  }
  return {
    status: 'success',
    version: BACKEND_VERSION,
    message: existing ? 'Row updated (same row)' : 'Row created',
  };
}

// ---------- Config: reads (drives every group/part/line list) ----------

function getConfigSheet() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(CONFIG_SHEET);
  if (!sheet) throw new Error(CONFIG_SHEET + ' sheet tab not found');
  return sheet;
}

function getConfigRows() {
  return getAllRowsAsObjects(getConfigSheet());
}

// Groups = distinct Group values from "group" rows UNION any Group value
// seen on a "part" row (so a group is never silently dropped even if its
// stub row was deleted by hand). Preserves sheet row order, not sorted.
function getConfigGroups(module) {
  var rows = getConfigRows();
  var groups = [];
  var seen = {};
  rows.forEach(function (r) {
    if (String(r.Module).toLowerCase() !== module) return;
    if ((r.Kind === 'group' || r.Kind === 'part') && r.Group) {
      var g = String(r.Group);
      if (!seen[g]) {
        seen[g] = true;
        groups.push(g);
      }
    }
  });
  return groups;
}

function getConfigParts(module, group) {
  var rows = getConfigRows();
  var parts = [];
  rows.forEach(function (r) {
    if (String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
        String(r.Group) === group && r.Value) {
      parts.push(String(r.Value));
    }
  });
  return parts;
}

// Machining-only, global (not tied to a customer or part).
function getConfigLines() {
  var rows = getConfigRows();
  var lines = [];
  rows.forEach(function (r) {
    if (String(r.Module).toLowerCase() === 'machining' && r.Kind === 'line' && r.Value) {
      lines.push(String(r.Value));
    }
  });
  return lines;
}

function getConfigSnapshot(module) {
  module = String(module || 'casting').toLowerCase();
  var groups = getConfigGroups(module);
  var partsByGroup = {};
  groups.forEach(function (g) {
    partsByGroup[g] = getConfigParts(module, g);
  });
  var result = { groups: groups, partsByGroup: partsByGroup };
  if (module === 'machining') result.lines = getConfigLines();
  return { status: 'success', data: result };
}

// ---------- Analytics: daily trend totals for the Dashboard tab ----------
//
// Sums Output (Actual for Secondary) and Rejection (Machining only) across
// EVERY group/part/line for the module, per calendar day, plus the average
// LOR% for that day. Missing days in the window are zero-filled so the
// chart still shows a full N-day axis even with sparse data.

function getAnalytics(module, days) {
  module = module || 'casting';
  days = parseInt(days, 10);
  if (!days || days < 1) days = 14;
  if (days > 90) days = 90;

  // Casting and Secondary each live in two sheets (Day + Night); read and
  // concatenate both so a day's total reflects both shifts. Both shifts share
  // the same shift-date, so grouping by Date alone (below) already merges them
  // into one bucket. A day row has no night slot columns (and vice versa), so
  // the union of outputKeys/lorKeys below simply skips the columns a row lacks.
  var rows;
  if (module === 'casting') {
    rows = getAllRowsAsObjects(getCastingSheetForShift('Day'))
      .concat(getAllRowsAsObjects(getCastingSheetForShift('Night')));
  } else if (module === 'secondary') {
    rows = getAllRowsAsObjects(getSecondarySheetForShift('Day'))
      .concat(getAllRowsAsObjects(getSecondarySheetForShift('Night')));
  } else {
    rows = getAllRowsAsObjects(getModuleSheet(module));
  }
  var tz = Session.getScriptTimeZone();

  var dateKeys = [];
  var today = new Date();
  for (var i = days - 1; i >= 0; i--) {
    var d = new Date(today.getTime() - i * 24 * 60 * 60 * 1000);
    dateKeys.push(Utilities.formatDate(d, tz, 'yyyy-MM-dd'));
  }

  var outputPrefix = (module === 'secondary') ? 'Actual_' : 'Output_';
  var lorPrefix = (module === 'secondary') ? 'LOR_' : 'Output_LOR';
  // Casting and Secondary split into Day+Night shift columns — sum the full
  // union so a day's total reflects both shifts. Both shifts share the same
  // shift-date, so grouping by Date alone (below) puts them in one bucket.
  var timeSlots = (module === 'casting' || module === 'secondary')
    ? DAY_SLOTS.concat(NIGHT_SLOTS)
    : OUTPUT_TIME_SLOTS;
  var outputKeys = timeSlots.map(function (s) { return outputPrefix + s; });
  var lorKeys = timeSlots.map(function (s) { return lorPrefix + s; });
  var rejectionKeys = (module === 'machining')
    ? OUTPUT_TIME_SLOTS.map(function (s) { return 'Rejection_' + s; })
    : [];

  var byDate = {};
  dateKeys.forEach(function (dk) {
    byDate[dk] = { output: 0, lorSum: 0, lorCount: 0, rejection: 0 };
  });

  rows.forEach(function (r) {
    var dk = formatDateOnly(r.Date);
    if (!byDate.hasOwnProperty(dk)) return;
    var bucket = byDate[dk];

    outputKeys.forEach(function (k) {
      var v = parseFloat(r[k]);
      if (!isNaN(v)) bucket.output += v;
    });

    lorKeys.forEach(function (k) {
      var raw = r[k];
      if (raw === '' || raw === null || raw === undefined) return;
      var s = String(raw);
      var pct;
      if (s.indexOf('%') !== -1) {
        pct = parseFloat(s); // already a percent, e.g. "33%"
      } else {
        var n = parseFloat(s);
        if (isNaN(n)) return;
        pct = n * 100; // Sheets stores a written "10%" as the fraction 0.1
      }
      if (isNaN(pct)) return;
      bucket.lorSum += pct;
      bucket.lorCount += 1;
    });

    rejectionKeys.forEach(function (k) {
      var v = parseFloat(r[k]);
      if (!isNaN(v)) bucket.rejection += v;
    });
  });

  var output = [];
  var lorPercent = [];
  var rejection = [];
  dateKeys.forEach(function (dk) {
    var b = byDate[dk];
    output.push(Math.round(b.output * 10) / 10);
    lorPercent.push(b.lorCount > 0 ? Math.round((b.lorSum / b.lorCount) * 10) / 10 : null);
    rejection.push(Math.round(b.rejection * 10) / 10);
  });

  var result = { dates: dateKeys, output: output, lorPercent: lorPercent };
  if (module === 'machining') result.rejection = rejection;
  return { status: 'success', data: result };
}

// ---------- Config: mutate (add / delete / rename groups, parts, lines) ----------
//
// Group deletes/renames CASCADE to every part row under that group, because
// part rows carry the group name in their own Group column — filtering by
// Group alone naturally sweeps up both the group's stub row and its parts.
// This only ever touches the Config sheet; historical production rows in
// Casting/Secondary/Machining are never modified or deleted by this.

function configMutate(payload) {
  var op = payload.op;
  var module = String(payload.module || '').toLowerCase();
  var kind = payload.kind; // 'group' | 'part' | 'line'
  var group = payload.group !== undefined && payload.group !== null ? String(payload.group) : '';
  var value = payload.value !== undefined && payload.value !== null ? String(payload.value) : '';
  var newValue = payload.newValue !== undefined && payload.newValue !== null ? String(payload.newValue) : '';

  if (!module) return { status: 'error', message: 'module is required' };
  if (['group', 'part', 'line'].indexOf(kind) === -1) {
    return { status: 'error', message: 'kind must be group, part or line' };
  }
  if (kind === 'part' && !group) {
    return { status: 'error', message: 'group is required for kind=part' };
  }

  var sheet = getConfigSheet();
  var headers = getHeaders(sheet);
  var groupCol = headers.indexOf('Group') + 1;
  var valueCol = headers.indexOf('Value') + 1;
  var rows = getAllRowsAsObjects(sheet);

  if (op === 'add') {
    if (!value) return { status: 'error', message: 'value is required' };
    if (kind === 'group') {
      // A group's own name lives in the Group column (so getConfigGroups,
      // and the delete/rename cascade below, can find it) — NOT the Value
      // column, unlike part/line rows where Value holds the item's name.
      var dupGroup = rows.some(function (r) {
        return String(r.Module).toLowerCase() === module && String(r.Group || '') === value;
      });
      if (dupGroup) return { status: 'error', message: 'Already exists' };
      sheet.appendRow([module, 'group', value, '']);
      return { status: 'success', version: BACKEND_VERSION, message: 'Added' };
    }
    var dup = rows.some(function (r) {
      return String(r.Module).toLowerCase() === module && r.Kind === kind &&
        String(r.Group || '') === group && String(r.Value || '') === value;
    });
    if (dup) return { status: 'error', message: 'Already exists' };
    sheet.appendRow([module, kind, group, value]);
    return { status: 'success', version: BACKEND_VERSION, message: 'Added' };
  }

  if (op === 'delete') {
    if (kind === 'group') {
      var toDelete = rows.filter(function (r) {
        return String(r.Module).toLowerCase() === module && String(r.Group || '') === value;
      });
      if (toDelete.length === 0) return { status: 'error', message: 'Not found' };
      deleteConfigRows(sheet, toDelete);
      return { status: 'success', version: BACKEND_VERSION, message: 'Deleted group and its parts' };
    }
    var target = rows.filter(function (r) {
      return String(r.Module).toLowerCase() === module && r.Kind === kind &&
        String(r.Group || '') === group && String(r.Value || '') === value;
    });
    if (target.length === 0) return { status: 'error', message: 'Not found' };
    deleteConfigRows(sheet, target);
    return { status: 'success', version: BACKEND_VERSION, message: 'Deleted' };
  }

  if (op === 'rename') {
    if (!newValue) return { status: 'error', message: 'newValue is required' };
    if (kind === 'group') {
      var groupRows = rows.filter(function (r) {
        return String(r.Module).toLowerCase() === module && String(r.Group || '') === value;
      });
      if (groupRows.length === 0) return { status: 'error', message: 'Not found' };
      groupRows.forEach(function (r) {
        sheet.getRange(r._rowNum, groupCol).setValue(newValue);
      });
      return { status: 'success', version: BACKEND_VERSION, message: 'Renamed group' };
    }
    var partRow = rows.find(function (r) {
      return String(r.Module).toLowerCase() === module && r.Kind === kind &&
        String(r.Group || '') === group && String(r.Value || '') === value;
    });
    if (!partRow) return { status: 'error', message: 'Not found' };
    sheet.getRange(partRow._rowNum, valueCol).setValue(newValue);
    return { status: 'success', version: BACKEND_VERSION, message: 'Renamed' };
  }

  return { status: 'error', message: 'Unknown op' };
}

// Deletes rows bottom-to-top so earlier row numbers stay valid as later
// deletes shift the sheet up.
function deleteConfigRows(sheet, rowsToDelete) {
  var rowNums = rowsToDelete
    .map(function (r) { return r._rowNum; })
    .sort(function (a, b) { return b - a; });
  rowNums.forEach(function (rowNum) {
    sheet.deleteRow(rowNum);
  });
}

// ---------- One-time setup: run manually from the Apps Script editor ----------
//
// Populates the Config sheet with the entities the app currently ships with
// (1212/3131/4141, ST1-3, Mazda/Proton/Toyota, Line 1-3). Select this
// function in the editor toolbar and click Run once, after creating the
// Config tab with its header row. Refuses to run if the sheet already has
// data, so it's safe to leave in place.
function seedDefaultConfig() {
  var sheet = getConfigSheet();
  var existing = getAllRowsAsObjects(sheet);
  if (existing.length > 0) {
    throw new Error('Config sheet already has rows — seed only runs on an empty sheet.');
  }

  var rows = [];
  function addGroup(module, group) { rows.push([module, 'group', group, '']); }
  function addPart(module, group, part) { rows.push([module, 'part', group, part]); }
  function addLine(line) { rows.push(['machining', 'line', '', line]); }

  addGroup('casting', '1212');
  ['1', '2', '3', '4'].forEach(function (p) { addPart('casting', '1212', p); });
  addGroup('casting', '3131');
  ['5', '6', '7'].forEach(function (p) { addPart('casting', '3131', p); });
  addGroup('casting', '4141');
  ['8', '9', '10'].forEach(function (p) { addPart('casting', '4141', p); });

  addGroup('secondary', 'ST1');
  ['P1', 'P2', 'P3'].forEach(function (p) { addPart('secondary', 'ST1', p); });
  addGroup('secondary', 'ST2');
  ['P4', 'P5', 'P6'].forEach(function (p) { addPart('secondary', 'ST2', p); });
  addGroup('secondary', 'ST3');
  ['P7', 'P8', 'P9'].forEach(function (p) { addPart('secondary', 'ST3', p); });

  addGroup('machining', 'Mazda');
  ['1', '2', '3'].forEach(function (p) { addPart('machining', 'Mazda', p); });
  addGroup('machining', 'Proton');
  ['4', '5', '6'].forEach(function (p) { addPart('machining', 'Proton', p); });
  addGroup('machining', 'Toyota');
  ['7', '8', '9'].forEach(function (p) { addPart('machining', 'Toyota', p); });
  ['Line 1', 'Line 2', 'Line 3'].forEach(addLine);

  sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, 4).setValues(rows);
  Logger.log('Seeded ' + rows.length + ' config rows.');
}

// ---------- One-time setup: run manually to create the shift sheet tabs ----------
//
// Each of these creates a module's two shift tabs (…_Day / …_Night) with the
// correct header row, and ensures Config has its MO column. Run the one you
// need ONCE from the Apps Script editor (pick it in the function dropdown,
// click Run) after pasting this code. Idempotent: skips a tab that already
// exists (only refreshing its header row if it drifted), never touches
// existing data, and never deletes the old single-sheet tab — remove that
// yourself once you've confirmed the two new tabs work.

function setupCastingShiftSheets() {
  createShiftSheets([
    { name: CASTING_DAY_SHEET, headers: castingHeadersForShift('Day') },
    { name: CASTING_NIGHT_SHEET, headers: castingHeadersForShift('Night') },
  ]);
}

function setupSecondaryShiftSheets() {
  createShiftSheets([
    { name: SECONDARY_DAY_SHEET, headers: secondaryHeadersForShift('Day') },
    { name: SECONDARY_NIGHT_SHEET, headers: secondaryHeadersForShift('Night') },
  ]);
}

function createShiftSheets(specs) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  specs.forEach(function (spec) {
    var sheet = ss.getSheetByName(spec.name);
    if (!sheet) {
      sheet = ss.insertSheet(spec.name);
      log.push('Created sheet: ' + spec.name);
    } else {
      log.push('Sheet already exists: ' + spec.name);
    }
    // Write/refresh the header row (safe — only row 1, matched by name later).
    var current = sheet.getLastColumn() > 0
      ? sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].join('|')
      : '';
    if (current !== spec.headers.join('|')) {
      sheet.getRange(1, 1, 1, spec.headers.length).setValues([spec.headers]);
      sheet.setFrozenRows(1);
      log.push('  set header row (' + spec.headers.length + ' cols)');
    }
  });

  var configSheet = getConfigSheet();
  var configHeaders = getHeaders(configSheet);
  if (configHeaders.indexOf('MO') === -1) {
    configSheet.getRange(1, configSheet.getLastColumn() + 1).setValue('MO');
    log.push('Added Config!MO column');
  }

  Logger.log(log.join('\n'));
}

// ---------- Helpers ----------

// Machining only now. Casting and Secondary are each split across two shift
// sheets — use getCastingSheetForShift/getSecondarySheetForShift for them.
function getModuleSheet(module) {
  if (module === 'machining') return requireSheet(MACHINING_SHEET);
  throw new Error('getModuleSheet: unsupported module "' + module + '"');
}

function requireSheet(sheetName, setupFn) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  if (!sheet) {
    throw new Error(setupFn
      ? sheetName + ' sheet tab not found — run ' + setupFn + '() once'
      : sheetName + ' sheet tab not found');
  }
  return sheet;
}

// Trim every header so a stray space in a header cell (e.g. "Date ") can't
// silently break column matching — the #1 cause of blank Date / new-row-each-
// submit. Values are still written positionally, so trimming is safe.
function getHeaders(sheet) {
  return sheet
    .getRange(1, 1, 1, sheet.getLastColumn())
    .getValues()[0]
    .map(function (h) {
      return String(h).trim();
    });
}

function getAllRowsAsObjects(sheet) {
  var headers = getHeaders(sheet);
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  var values = sheet.getRange(2, 1, lastRow - 1, headers.length).getValues();
  return values.map(function (v, i) {
    var obj = {};
    headers.forEach(function (h, j) { obj[h] = v[j]; });
    obj._rowNum = i + 2;
    return obj;
  });
}

function getTodayString() {
  return Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd');
}

function formatDateOnly(dateVal) {
  if (!dateVal) return '';
  return Utilities.formatDate(new Date(dateVal), Session.getScriptTimeZone(), 'yyyy-MM-dd');
}

function hhmm(dateVal) {
  return Utilities.formatDate(new Date(dateVal), Session.getScriptTimeZone(), 'HH:mm');
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(
    ContentService.MimeType.JSON
  );
}
