/**
 * HICOM Production Log — Apps Script reference.
 *
 * Unified incremental upsert backend for Casting, Secondary, and Machining.
 * ALL THREE now run the same real 2-shift schedule (Day 8AM-6PM, Night
 * 8PM-6AM crossing midnight), each split into two per-shift sheet tabs with
 * no Shift column, keyed by their selectors + shift-date (see getShiftDate).
 * Casting/Secondary key on (DCM|Station) + Part; Machining adds a third
 * selector, Line, so it keys on Customer + Part + Line. Parts in all three
 * carry an MO number, snapshotted onto a row once at creation.
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
 *   MO (part rows, all three modules — see getConfigPartMo): the part's
 *     current manufacturing order number, editable from the app; blank/unused
 *     for group/line rows. Added by the setup*ShiftSheets() migrations.
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
 * Machining (shift-split like the others — two tabs, keyed Customer+PartNo+
 * Line+shift-date, MO per part. Run setupMachiningShiftSheets() once):
 *
 *   Machining_Day (Day shift, checkpoints 8AM-6PM) / Machining_Night (8PM-6AM):
 *     Date | Customer | PartNo | Line | Barcode | PartName | MO | Plan |
 *     Output_<slot> | Output_LOR<slot> (x6) | LastUpdated
 *
 *   Machining_Rejections — rejections are a typed LIST per entry, not one
 *   number per slot, so they live here, one row per defect type:
 *     Date | Shift | Customer | PartNo | Line | Barcode | PartName | MO |
 *     RejectionCode | RejectionType | Qty | LastUpdated
 *   The app always posts the whole list, which replaces that entry's rows.
 *   The machining row also carries RejectionTotal (a number) and
 *   RejectionSummary ("5 POROSITY, 3 FLASHES"), rewritten from the list on
 *   every save so the entry reads at a glance.
 *
 *   Rejection_Summary — live QUERY rollups by defect type and by part.
 *   Run setupRejectionSummary() once; it never needs re-running.
 *
 * After editing: Deploy > New deployment (editing an existing deployment's
 * version has not reliably gone live in testing — always cut a new one).
 */

var SECRET_KEY = 'hicom2026changeme';
var CONFIG_SHEET = 'Config';
// Master parts list, imported from the plant CSV. Header row (row 1) must be
// EXACTLY: Part number | Part name | Part code | Department
// The app's add-part dropdown reads part codes from here, filtered by the
// module's Department; the chosen code's Part number (barcode) and Part name
// are snapshotted onto the Config part row and every logged data row.
var PARTS_SHEET = 'Parts';

// Master defect list, imported from the plant CSV. The export carries a title
// line above the real header, so the reader finds the header row rather than
// assuming row 1 (see getRejectionTypes).
var REJECTION_TYPES_SHEET = 'RejectionTypes';

// Machining rejections are a LIST per entry (5 POROSITY, 2 COLD SHUT, ...),
// not one number per time slot, so they get their own fact table: one row per
// defect type per Customer+Part+Line+shift+date. That keeps the shape open
// ended and makes "which defect costs us most" a plain pivot.
var MACHINING_REJECTIONS_SHEET = 'Machining_Rejections';

// A small always-current rollup of the detail table (RejectionType | Qty),
// built as a live QUERY formula rather than rows the script maintains — a
// formula can never be left stale by a save that didn't run.
var REJECTION_SUMMARY_SHEET = 'Rejection_Summary';

function machiningRejectionHeaders() {
  return ['Date', 'Shift', 'Customer', 'PartNo', 'Line', 'Barcode', 'PartName',
    'MO', 'RejectionCode', 'RejectionType', 'Qty', 'LastUpdated'];
}

// Which "Department" value in the Parts master belongs to each app module.
function moduleDepartment(module) {
  if (module === 'secondary') return 'secondary';
  if (module === 'machining') return 'machining';
  return 'casting';
}

// ALL THREE modules run the same real 2-shift schedule. Day checkpoints run
// 8AM-6PM; Night checkpoints run 8PM-6AM (crossing midnight).
//
// Each shift is its OWN sheet tab (Casting_Day/Casting_Night,
// Secondary_Day/Secondary_Night, Machining_Day/Machining_Night) so every row
// holds only its shift's six checkpoints — no half-empty rows, and no Shift
// column (the tab the row lives in IS the shift). Column prefixes differ per
// module (Casting and Machining Output_/Output_LOR; Secondary Actual_/LOR_)
// but the slot TIMES are identical.
var CASTING_DAY_SHEET = 'Casting_Day';
var CASTING_NIGHT_SHEET = 'Casting_Night';
var SECONDARY_DAY_SHEET = 'Secondary_Day';
var SECONDARY_NIGHT_SHEET = 'Secondary_Night';
var MACHINING_DAY_SHEET = 'Machining_Day';
var MACHINING_NIGHT_SHEET = 'Machining_Night';
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

// The sheet tab a Machining row lives in, chosen purely by shift.
function getMachiningSheetForShift(shift) {
  var name = shift === 'Night' ? MACHINING_NIGHT_SHEET : MACHINING_DAY_SHEET;
  return requireSheet(name, 'setupMachiningShiftSheets');
}

// Header frame for a Casting shift sheet, built from that shift's slots.
// The part's identity columns (PartNo = master code, Barcode = the CSV "Part
// number", PartName) sit together right after the machine/station selector,
// then MO and Plan, then the slots, with LastUpdated last.
//
// Everything reads and writes by header NAME, so this order is purely for
// humans reading the sheet — but existing tabs must be physically rearranged
// to match: run migrateColumnOrder() once (see below).
function castingHeadersForShift(shift) {
  var headers = ['Date', 'DCM', 'PartNo', 'Barcode', 'PartName', 'MO', 'Plan'];
  slotsForShift(shift).forEach(function (slot) {
    headers.push('Output_' + slot);
    headers.push('Output_LOR' + slot);
  });
  headers.push('LastUpdated');
  return headers;
}

// Header frame for a Machining shift sheet — like Casting but one level
// deeper (Line). Rejections used to be one count per time slot; they are now
// a typed list in MACHINING_REJECTIONS_SHEET, so this frame is output-only.
function machiningHeadersForShift(shift) {
  var headers = ['Date', 'Customer', 'PartNo', 'Line', 'Barcode', 'PartName', 'MO', 'Plan'];
  slotsForShift(shift).forEach(function (slot) {
    headers.push('Output_' + slot);
    headers.push('Output_LOR' + slot);
  });
  // Derived from the detail table on every save — read these, never type them.
  headers.push('RejectionTotal', 'RejectionSummary', 'LastUpdated');
  return headers;
}

// Header frame for a Secondary shift sheet — same shape as Casting but keyed
// by Station and using the Actual_/LOR_ column prefixes.
function secondaryHeadersForShift(shift) {
  var headers = ['Date', 'Station', 'PartNo', 'Barcode', 'PartName', 'MO', 'Plan'];
  slotsForShift(shift).forEach(function (slot) {
    headers.push('Actual_' + slot);
    headers.push('LOR_' + slot);
  });
  headers.push('LastUpdated');
  return headers;
}

// Config's own frame: the part's identity (Value = code, Barcode, PartName)
// grouped, with the monthly MO last since it's the one that gets edited.
var CONFIG_HEADERS = ['Module', 'Kind', 'Group', 'Value', 'Barcode', 'PartName', 'MO'];

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
var BACKEND_VERSION = 'REJECTION-ROLLUP-v9';

function doGet(e) {
  try {
    var action = e && e.parameter ? e.parameter.action : null;
    var module = e && e.parameter ? e.parameter.module : null;

    if (action === 'config') return jsonResponse(getConfigSnapshot(module));
    if (action === 'analytics') return jsonResponse(getAnalytics(module, e.parameter.days));
    if (action === 'partcodes') return jsonResponse(getPartMaster(module));
    if (action === 'rejectiontypes') return jsonResponse(getRejectionTypes());

    if (module === 'machining') {
      // Machining is now shift-aware too (Machining_Day/Machining_Night) and
      // one level deeper: Customer -> Part -> Line -> entry. Every call
      // carries a shift.
      var mShift = e.parameter.shift;
      if (action === 'dashboard') return jsonResponse(getMachiningDashboard(mShift));
      if (action === 'parts') return jsonResponse(getMachiningParts(e.parameter.customer, mShift));
      if (action === 'lines') return jsonResponse(getMachiningLines(e.parameter.customer, e.parameter.part, mShift));
      if (action === 'row') {
        return jsonResponse(getMachiningRow(e.parameter.customer, e.parameter.part, e.parameter.line, mShift));
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
      // Part ops that also carry an MO number (all three modules now) —
      // everything else (groups, lines) stays on the generic configMutate.
      if (payload.op === 'castingAddPart') return jsonResponse(addPartWithMo('casting', payload));
      if (payload.op === 'castingEditPart') return jsonResponse(editPartWithMo('casting', payload));
      if (payload.op === 'secondaryAddPart') return jsonResponse(addPartWithMo('secondary', payload));
      if (payload.op === 'secondaryEditPart') return jsonResponse(editPartWithMo('secondary', payload));
      if (payload.op === 'machiningAddPart') return jsonResponse(addPartWithMo('machining', payload));
      if (payload.op === 'machiningEditPart') return jsonResponse(editPartWithMo('machining', payload));
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
    var info = getConfigPartInfo('secondary', station, part);
    return {
      part: part,
      mo: info.mo,
      name: info.name,
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
    var pinfo = getConfigPartInfo('secondary', data.Station, data.PartNo);
    merged.MO = pinfo.mo;
    merged.Barcode = pinfo.barcode;
    merged.PartName = pinfo.name;
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
    var info = getConfigPartInfo('casting', dcm, part);
    return {
      part: part,
      mo: info.mo,
      name: info.name,
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
    // Snapshot the part's CURRENTLY configured MO + Barcode + PartName onto the
    // row exactly once, at creation. If Config changes later (new month, part
    // re-picked), rows already logged keep what was active when written — a
    // later Config edit must never silently rewrite already-logged history.
    var pinfo = getConfigPartInfo('casting', data.DCM, data.PartNo);
    merged.MO = pinfo.mo;
    merged.Barcode = pinfo.barcode;
    merged.PartName = pinfo.name;
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

// A part's snapshot attributes, read from its Config row: MO, plus the
// Barcode (CSV "Part number") and PartName carried over from the master when
// the part was added. Blank strings when the part or columns don't exist.
function getConfigPartInfo(module, group, part) {
  var rows = getConfigRows();
  var match = rows.find(function (r) {
    return String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
      String(r.Group) === group && String(r.Value) === part;
  });
  if (!match) return { mo: '', barcode: '', name: '' };
  return {
    mo: match.MO ? String(match.MO) : '',
    barcode: match.Barcode ? String(match.Barcode) : '',
    name: match.PartName ? String(match.PartName) : '',
  };
}

// Back-compat thin wrapper (still used by the get*Parts readers).
function getConfigPartMo(module, group, part) {
  return getConfigPartInfo(module, group, part).mo;
}

// ---------- Parts master (imported CSV) ----------
//
// getPartMaster feeds the app's add-part dropdown: the distinct Part codes for
// this module's Department, each with its barcode + name. lookupMasterPart
// resolves a chosen code back to its barcode/name at add-time.

function getPartMaster(module) {
  module = String(module || 'casting').toLowerCase();
  var dept = moduleDepartment(module);
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(PARTS_SHEET);
  if (!sheet) {
    return { status: 'error', message: PARTS_SHEET + ' sheet not found — create it and import the parts CSV' };
  }
  if (getHeaders(sheet).length === 0) {
    return {
      status: 'error',
      message: 'The ' + PARTS_SHEET + ' sheet is empty — import the parts CSV into it ' +
        '(if the import made its own tab, delete this one and rename that tab to ' + PARTS_SHEET + ')',
    };
  }
  var rows = getPartsMasterRows(sheet);
  var seen = {};
  var out = [];
  rows.forEach(function (r) {
    if (String(r.Department || '').toLowerCase().trim() !== dept) return;
    var code = String(r['Part code'] === undefined ? '' : r['Part code']).trim();
    if (!code || seen[code]) return;   // distinct codes; first row wins on dupes
    seen[code] = true;
    out.push({
      code: code,
      barcode: String(r['Part number'] === undefined ? '' : r['Part number']).trim(),
      name: String(r['Part name'] === undefined ? '' : r['Part name']).trim(),
    });
  });
  return { status: 'success', data: out };
}

// ---------- Rejection types master ----------
//
// Feeds the defect-type picker on the Machining entry screen. The CSV export
// looks like:
//     REJECTION CODES/CAUSE CODES        <- title line
//     REJECTION CODES | REJECTION TYPE   <- the actual header
//     001             | ALARM
// so rather than assuming row 1 is the header, scan the first few rows for it.
// That way the sheet works whether or not the title line was deleted.
function getRejectionTypes() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(REJECTION_TYPES_SHEET);
  if (!sheet) {
    return { status: 'error', message: REJECTION_TYPES_SHEET + ' sheet not found — create it and import the rejection CSV' };
  }
  var lastRow = sheet.getLastRow();
  var lastCol = sheet.getLastColumn();
  if (lastRow < 1 || lastCol < 1) {
    return { status: 'error', message: 'The ' + REJECTION_TYPES_SHEET + ' sheet is empty — import the rejection CSV into it' };
  }
  var values = sheet.getRange(1, 1, lastRow, lastCol).getValues();

  var headerRow = -1, typeCol = -1, codeCol = -1;
  for (var i = 0; i < Math.min(values.length, 10) && headerRow === -1; i++) {
    for (var j = 0; j < values[i].length; j++) {
      var cell = String(values[i][j]).trim().toUpperCase();
      if (cell === 'REJECTION TYPE') { headerRow = i; typeCol = j; }
      if (cell === 'REJECTION CODES' || cell === 'REJECTION CODE') { codeCol = j; }
    }
  }
  if (headerRow === -1) {
    return {
      status: 'error',
      message: 'No "REJECTION TYPE" header found in ' + REJECTION_TYPES_SHEET +
        ' — the sheet needs a header row with REJECTION CODES and REJECTION TYPE',
    };
  }
  if (codeCol === -1) codeCol = typeCol > 0 ? typeCol - 1 : 0;

  var out = [], seen = {};
  for (var r = headerRow + 1; r < values.length; r++) {
    var type = String(values[r][typeCol]).trim();
    if (!type) continue;
    var code = padRejectionCode(values[r][codeCol]);
    // A few names repeat under different codes (FOLDED is 153 and 179), so the
    // code is part of the identity.
    var key = code + '|' + type;
    if (seen[key]) continue;
    seen[key] = true;
    out.push({ code: code, type: type });
  }
  return { status: 'success', data: out };
}

// A CSV import reads "001" as the number 1 — put the leading zeros back so the
// code still matches the printed defect list.
function padRejectionCode(raw) {
  if (raw === null || raw === undefined) return '';
  var s = String(raw).trim();
  if (s === '') return '';
  if (/^\d+$/.test(s) && s.length < 3) s = ('00' + s).slice(-3);
  return s;
}

function lookupMasterPart(module, code) {
  var dept = moduleDepartment(String(module || '').toLowerCase());
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(PARTS_SHEET);
  if (!sheet || getHeaders(sheet).length === 0) return { barcode: '', name: '' };
  var wanted = String(code).trim();
  var match = getPartsMasterRows(sheet).find(function (r) {
    return String(r.Department || '').toLowerCase().trim() === dept &&
      String(r['Part code'] === undefined ? '' : r['Part code']).trim() === wanted;
  });
  if (!match) return { barcode: '', name: '' };
  return {
    barcode: String(match['Part number'] === undefined ? '' : match['Part number']).trim(),
    name: String(match['Part name'] === undefined ? '' : match['Part name']).trim(),
  };
}

// Append a Config row built by HEADER NAME, so Barcode/PartName land in the
// right columns whatever order the Config sheet has them in.
function writeConfigRow(sheet, obj) {
  var headers = getHeaders(sheet);
  var arr = headers.map(function (h) { return obj.hasOwnProperty(h) ? obj[h] : ''; });
  sheet.appendRow(arr);
  invalidateCaches();
}

// Shared by all three modules. `payload.part` is now a Part CODE chosen from
// the master dropdown; we look its barcode + name up and store them alongside
// the MO on the Config part row. Wire ops: castingAddPart/secondaryAddPart/…
function addPartWithMo(module, payload) {
  var group = String(payload.group || '');
  var part = String(payload.part || '').trim();   // the chosen Part CODE
  var mo = payload.mo !== undefined && payload.mo !== null ? String(payload.mo) : '';
  if (!group || !part) return { status: 'error', message: 'group and part are required' };

  var sheet = getConfigSheet();
  var rows = getAllRowsAsObjects(sheet);
  var dup = rows.some(function (r) {
    return String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
      String(r.Group) === group && String(r.Value) === part;
  });
  if (dup) return { status: 'error', message: 'Already exists' };

  var info = lookupMasterPart(module, part);
  writeConfigRow(sheet, {
    Module: module, Kind: 'part', Group: group, Value: part,
    MO: mo, Barcode: info.barcode, PartName: info.name,
  });
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
  var barcodeCol = headers.indexOf('Barcode') + 1;
  var nameCol = headers.indexOf('PartName') + 1;
  var rows = getAllRowsAsObjects(sheet);
  var match = rows.find(function (r) {
    return String(r.Module).toLowerCase() === module && r.Kind === 'part' &&
      String(r.Group) === group && String(r.Value) === part;
  });
  if (!match) return { status: 'error', message: 'Not found' };
  if (newPart !== part) {
    // Code changed -> re-resolve its barcode/name from the master.
    sheet.getRange(match._rowNum, valueCol).setValue(newPart);
    var info = lookupMasterPart(module, newPart);
    if (barcodeCol > 0) sheet.getRange(match._rowNum, barcodeCol).setValue(info.barcode);
    if (nameCol > 0) sheet.getRange(match._rowNum, nameCol).setValue(info.name);
  }
  if (mo !== null && moCol > 0) sheet.getRange(match._rowNum, moCol).setValue(mo);
  invalidateCaches();
  return { status: 'success', version: BACKEND_VERSION, message: 'Updated' };
}

// ---------- Machining: reads (shift-aware — Customer -> Part -> Line -> entry) ----------
//
// Now mirrors Casting/Secondary: two per-shift sheets (Machining_Day/
// Machining_Night), keyed by Customer + PartNo + Line + shift-date. Adds the
// Line dimension; rejections are a typed list in MACHINING_REJECTIONS_SHEET.
// MO is per-PART (scoped to Customer+Part), shared across that part's lines.

function getMachiningDashboard(shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getMachiningSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var customers = getConfigGroups('machining');
  var result = customers.map(function (customer) {
    var latest = null;
    rows.forEach(function (r) {
      if (String(r.Customer) === customer && formatDateOnly(r.Date) === shiftDate && r.LastUpdated) {
        if (!latest || new Date(r.LastUpdated) > new Date(latest)) latest = r.LastUpdated;
      }
    });
    return { dcm: customer, lastUpdated: latest ? hhmm(latest) : null };
  });
  return { status: 'success', data: result };
}

function getMachiningParts(customer, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getMachiningSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var parts = getConfigParts('machining', customer);
  var result = parts.map(function (part) {
    var latest = null;
    rows.forEach(function (r) {
      if (String(r.Customer) === customer && String(r.PartNo) === part &&
          formatDateOnly(r.Date) === shiftDate && r.LastUpdated) {
        if (!latest || new Date(r.LastUpdated) > new Date(latest)) latest = r.LastUpdated;
      }
    });
    var info = getConfigPartInfo('machining', customer, part);
    return {
      part: part,
      mo: info.mo,
      name: info.name,
      lastUpdated: latest ? hhmm(latest) : null,
    };
  });
  return { status: 'success', data: result };
}

function getMachiningLines(customer, part, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getMachiningSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var slots = slotsForShift(shift);
  var lines = getConfigLines();
  var result = lines.map(function (line) {
    var match = rows.find(function (r) {
      return String(r.Customer) === customer && String(r.PartNo) === part &&
        String(r.Line) === line && formatDateOnly(r.Date) === shiftDate;
    });
    var filled = 0;
    if (match) {
      slots.forEach(function (slot) {
        var v = match['Output_' + slot];
        if (v !== '' && v !== null && v !== undefined) filled++;
      });
    }
    return {
      part: line,
      lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null,
      fillPercent: match ? Math.round((filled / slots.length) * 100) : 0,
    };
  });
  return { status: 'success', data: result };
}

function getMachiningRow(customer, part, line, shift) {
  shift = shift === 'Night' ? 'Night' : 'Day';
  var rows = getAllRowsAsObjects(getMachiningSheetForShift(shift));
  var shiftDate = getShiftDate(shift);
  var match = rows.find(function (r) {
    return String(r.Customer) === customer && String(r.PartNo) === part &&
      String(r.Line) === line && formatDateOnly(r.Date) === shiftDate;
  });
  if (!match) return { status: 'success', data: null };
  delete match._rowNum;
  // The entry screen edits the defect list in place, so it ships with the row.
  match.Rejections = getMachiningRejections(customer, part, line, shift);
  return { status: 'success', data: match };
}

// ---------- Machining: upsert (per-shift sheet, snapshots MO, Rejection per slot) ----------

function upsertMachiningRow(data) {
  // `data.Shift` is sent by the app only to pick the sheet — never stored.
  var shift = data.Shift === 'Night' ? 'Night' : 'Day';
  var sheet = getMachiningSheetForShift(shift);
  var headers = getHeaders(sheet);
  var rows = getAllRowsAsObjects(sheet);
  var shiftDate = getShiftDate(shift);
  var slots = slotsForShift(shift);

  var existing = rows.find(function (r) {
    return String(r.Customer) === String(data.Customer) &&
      String(r.PartNo) === String(data.PartNo) &&
      String(r.Line) === String(data.Line) &&
      formatDateOnly(r.Date) === shiftDate;
  });

  var merged = existing ? Object.assign({}, existing) : {};
  merged.Date = shiftDate;
  merged.Customer = data.Customer;
  merged.PartNo = data.PartNo;
  merged.Line = data.Line;
  if (!existing) {
    // Snapshot the part's currently-configured MO onto the row once, at
    // creation — later Config MO edits never rewrite already-logged rows.
    // MO is per-part, so every line of a part logs the same MO.
    var pinfo = getConfigPartInfo('machining', data.Customer, data.PartNo);
    merged.MO = pinfo.mo;
    merged.Barcode = pinfo.barcode;
    merged.PartName = pinfo.name;
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

  // Parse the defect list before writing the row so its total and summary go
  // out in the same write. null = the field wasn't sent, so whatever the row
  // already carries stays.
  var rejections = parseRejectionList(data);
  if (rejections !== null) {
    var totals = summariseRejections(rejections);
    merged.RejectionTotal = totals.total;
    merged.RejectionSummary = totals.summary;
  }

  merged.LastUpdated = new Date();
  var rowArray = headers.map(function (h) {
    return merged.hasOwnProperty(h) ? merged[h] : '';
  });

  if (existing) {
    sheet.getRange(existing._rowNum, 1, 1, headers.length).setValues([rowArray]);
  } else {
    sheet.appendRow(rowArray);
  }

  if (rejections !== null) {
    writeMachiningRejections(rejections, data, shift, shiftDate, merged);
  }

  return {
    status: 'success',
    version: BACKEND_VERSION,
    message: existing ? 'Row updated (same row)' : 'Row created',
  };
}

// ---------- Machining: the rejection list ----------
//
// The app sends the WHOLE list as `data.Rejections` (a JSON array of
// {code, type, qty}), so this replaces every row for that entry rather than
// merging: deleting a line in the app has to delete it in the sheet too.
// A missing field means "not edited" and is left alone; an empty array clears.
//
// Returns the parsed list, or null when the field was absent or unusable —
// null means "leave everything as it was", which is why a malformed payload
// can never wipe a shift's defects.
function parseRejectionList(data) {
  if (data.Rejections === undefined || data.Rejections === null) return null;
  var list;
  try {
    list = typeof data.Rejections === 'string' ? JSON.parse(data.Rejections) : data.Rejections;
  } catch (e) {
    return null;
  }
  if (Object.prototype.toString.call(list) !== '[object Array]') return null;
  return list.filter(function (item) {
    // A half-filled UI row is not a defect.
    return item && String(item.qty === undefined ? '' : item.qty).trim() !== '' &&
      String(item.type === undefined ? '' : item.type).trim() !== '';
  });
}

// The two derived cells that ride on the machining row itself, so an entry
// reads at a glance without opening the detail table:
//   RejectionTotal   8                       (a NUMBER — sums and charts)
//   RejectionSummary "5 POROSITY, 3 FLASHES" (text, for humans)
// Both are rewritten from the list on every save, so they cannot drift.
function summariseRejections(list) {
  var total = 0;
  var parts = [];
  list.forEach(function (item) {
    var qty = parseFloat(item.qty);
    if (!isNaN(qty)) total += qty;
    parts.push(String(item.qty).trim() + ' ' + String(item.type).trim());
  });
  return { total: total, summary: parts.join(', ') };
}

function writeMachiningRejections(list, data, shift, shiftDate, row) {
  var sheet = requireSheet(MACHINING_REJECTIONS_SHEET, setupMachiningShiftSheets);
  var headers = getHeaders(sheet);

  var stale = getAllRowsAsObjects(sheet).filter(function (r) {
    return String(r.Customer) === String(data.Customer) &&
      String(r.PartNo) === String(data.PartNo) &&
      String(r.Line) === String(data.Line) &&
      String(r.Shift) === shift &&
      formatDateOnly(r.Date) === shiftDate;
  });
  if (stale.length) deleteSheetRows(sheet, stale);

  var now = new Date();
  list.forEach(function (item) {
    var qty = String(item.qty).trim();
    var qtyNum = parseFloat(qty);
    var out = {
      Date: shiftDate,
      Shift: shift,
      Customer: data.Customer,
      PartNo: data.PartNo,
      Line: data.Line,
      Barcode: row.Barcode || '',
      PartName: row.PartName || '',
      MO: row.MO || '',
      RejectionCode: padRejectionCode(item.code),
      RejectionType: String(item.type).trim(),
      // Written as a NUMBER, not text — the summary tab's QUERY sums this
      // column, and sum() silently ignores text cells.
      Qty: isNaN(qtyNum) ? qty : qtyNum,
      LastUpdated: now,
    };
    sheet.appendRow(headers.map(function (h) {
      return out.hasOwnProperty(h) ? out[h] : '';
    }));
  });
}

function getMachiningRejections(customer, part, line, shift) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(MACHINING_REJECTIONS_SHEET);
  if (!sheet || getHeaders(sheet).length === 0) return [];
  var shiftDate = getShiftDate(shift);
  return getAllRowsAsObjects(sheet)
    .filter(function (r) {
      return String(r.Customer) === String(customer) &&
        String(r.PartNo) === String(part) &&
        String(r.Line) === String(line) &&
        String(r.Shift) === shift &&
        formatDateOnly(r.Date) === shiftDate;
    })
    .map(function (r) {
      return {
        code: padRejectionCode(r.RejectionCode),
        type: String(r.RejectionType === undefined ? '' : r.RejectionType),
        qty: String(r.Qty === undefined ? '' : r.Qty),
      };
    });
}

// ---------- Config: reads (drives every group/part/line list) ----------

function getConfigSheet() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(CONFIG_SHEET);
  if (!sheet) throw new Error(CONFIG_SHEET + ' sheet tab not found');
  return sheet;
}

// ---------- Per-request caches ----------
//
// Apps Script gives every request a fresh process, so these live only for the
// current call — there is no cross-request staleness to worry about.
//
// They matter a lot: getConfigPartInfo runs once PER PART inside each
// get*Parts, and each call used to re-read the entire Config sheet. A 10-part
// screen meant 10 full sheet reads; now it's one. Same for the ~380-row Parts
// master. Sheet reads are by far the slowest thing this script does.
var _cache = {};

function invalidateCaches() {
  _cache = {};
}

function getConfigRows() {
  if (!_cache.configRows) {
    _cache.configRows = getAllRowsAsObjects(getConfigSheet());
  }
  return _cache.configRows;
}

// Rows of the Parts master, read at most once per request.
function getPartsMasterRows(sheet) {
  if (!_cache.partsRows) _cache.partsRows = getAllRowsAsObjects(sheet);
  return _cache.partsRows;
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

  // Every module now lives in two sheets (Day + Night); read and concatenate
  // both so a day's total reflects both shifts. Both shifts share the same
  // shift-date, so grouping by Date alone (below) already merges them into one
  // bucket. A day row has no night slot columns (and vice versa), so the union
  // of outputKeys/lorKeys below simply skips the columns a given row lacks.
  var rows;
  if (module === 'secondary') {
    rows = getAllRowsAsObjects(getSecondarySheetForShift('Day'))
      .concat(getAllRowsAsObjects(getSecondarySheetForShift('Night')));
  } else if (module === 'machining') {
    rows = getAllRowsAsObjects(getMachiningSheetForShift('Day'))
      .concat(getAllRowsAsObjects(getMachiningSheetForShift('Night')));
  } else {
    rows = getAllRowsAsObjects(getCastingSheetForShift('Day'))
      .concat(getAllRowsAsObjects(getCastingSheetForShift('Night')));
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
  // All modules split into Day+Night shift columns — sum the full union so a
  // day's total reflects both shifts. Both shifts share the same shift-date,
  // so grouping by Date alone (below) puts them in one bucket.
  var timeSlots = DAY_SLOTS.concat(NIGHT_SLOTS);
  var outputKeys = timeSlots.map(function (s) { return outputPrefix + s; });
  var lorKeys = timeSlots.map(function (s) { return lorPrefix + s; });
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

  });

  // Machining rejections are their own fact table now (one row per defect
  // type), so they're totalled per date from there instead of off the row.
  if (module === 'machining') {
    var rejSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(MACHINING_REJECTIONS_SHEET);
    if (rejSheet && getHeaders(rejSheet).length > 0) {
      getAllRowsAsObjects(rejSheet).forEach(function (r) {
        var dk = formatDateOnly(r.Date);
        if (!byDate.hasOwnProperty(dk)) return;
        var qty = parseFloat(r.Qty);
        if (!isNaN(qty)) byDate[dk].rejection += qty;
      });
    }
  }

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
      deleteSheetRows(sheet, toDelete);
      return { status: 'success', version: BACKEND_VERSION, message: 'Deleted group and its parts' };
    }
    var target = rows.filter(function (r) {
      return String(r.Module).toLowerCase() === module && r.Kind === kind &&
        String(r.Group || '') === group && String(r.Value || '') === value;
    });
    if (target.length === 0) return { status: 'error', message: 'Not found' };
    deleteSheetRows(sheet, target);
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
// Deletes rows bottom-up so earlier deletions don't shift later row numbers.
function deleteSheetRows(sheet, rowsToDelete) {
  var rowNums = rowsToDelete
    .map(function (r) { return r._rowNum; })
    .sort(function (a, b) { return b - a; });
  rowNums.forEach(function (rowNum) {
    sheet.deleteRow(rowNum);
  });
  invalidateCaches();
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

// ---------- Rejection rollup tab ----------
//
// Two live tables over Machining_Rejections: totals by defect type, and by
// part. Both are QUERY formulas, so they update the moment a log is saved and
// there is nothing to re-run. Safe to re-run — it rebuilds the formulas.
//
// The column letters are derived from machiningRejectionHeaders() rather than
// hardcoded, so moving a column in the detail table doesn't silently break it.
function setupRejectionSummary() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(REJECTION_SUMMARY_SHEET) || ss.insertSheet(REJECTION_SUMMARY_SHEET);
  sheet.clear();

  var headers = machiningRejectionHeaders();
  var typeCol = columnLetter(headers.indexOf('RejectionType') + 1);
  var qtyCol = columnLetter(headers.indexOf('Qty') + 1);
  var partCol = columnLetter(headers.indexOf('PartNo') + 1);
  var src = "'" + MACHINING_REJECTIONS_SHEET + "'!";

  sheet.getRange('A1').setValue('Rejections by type');
  sheet.getRange('A2').setFormula(
    '=QUERY(' + src + typeCol + ':' + qtyCol + ', "select ' + typeCol +
    ', sum(' + qtyCol + ') where ' + typeCol + " is not null and " + typeCol +
    " <> '' group by " + typeCol + ' order by sum(' + qtyCol + ") desc label " +
    typeCol + " 'RejectionType', sum(" + qtyCol + ") 'Qty'\", 1)"
  );

  sheet.getRange('D1').setValue('Rejections by part');
  sheet.getRange('D2').setFormula(
    '=QUERY(' + src + 'A:' + qtyCol + ', "select ' + partCol +
    ', sum(' + qtyCol + ') where ' + partCol + " is not null and " + partCol +
    " <> '' group by " + partCol + ' order by sum(' + qtyCol + ") desc label " +
    partCol + " 'PartNo', sum(" + qtyCol + ") 'Qty'\", 1)"
  );

  sheet.getRange('A1:D1').setFontWeight('bold');
  sheet.setColumnWidth(1, 240);
  sheet.setColumnWidth(4, 140);
  Logger.log('Built ' + REJECTION_SUMMARY_SHEET + ' (live formulas over ' +
    MACHINING_REJECTIONS_SHEET + ')');
}

// 1 -> "A", 27 -> "AA".
function columnLetter(index) {
  var out = '';
  while (index > 0) {
    var rem = (index - 1) % 26;
    out = String.fromCharCode(65 + rem) + out;
    index = Math.floor((index - 1) / 26);
  }
  return out;
}

function setupMachiningShiftSheets() {
  createShiftSheets([
    { name: MACHINING_DAY_SHEET, headers: machiningHeadersForShift('Day') },
    { name: MACHINING_NIGHT_SHEET, headers: machiningHeadersForShift('Night') },
    { name: MACHINING_REJECTIONS_SHEET, headers: machiningRejectionHeaders() },
    // (the Rejection_Summary rollup is formulas, not headers — built below)
  ]);
  setupRejectionSummary();
}

// ---------- One-off: rearrange existing tabs into the header order above ----
//
// Barcode/PartName were originally appended after LastUpdated so they could be
// added to live sheets without moving anything. This physically rewrites each
// tab so the part identity columns sit next to PartNo.
//
// Rewriting only row 1 would be data corruption — the values would stay put
// while the titles above them moved. So every row is re-mapped BY HEADER NAME.
// Columns not in the target frame are kept at the end rather than dropped.
// Safe to re-run: a tab already in the right order is left alone.
function migrateColumnOrder() {
  var log = [
    reorderSheet(CASTING_DAY_SHEET, castingHeadersForShift('Day')),
    reorderSheet(CASTING_NIGHT_SHEET, castingHeadersForShift('Night')),
    reorderSheet(SECONDARY_DAY_SHEET, secondaryHeadersForShift('Day')),
    reorderSheet(SECONDARY_NIGHT_SHEET, secondaryHeadersForShift('Night')),
    reorderSheet(MACHINING_DAY_SHEET, machiningHeadersForShift('Day')),
    reorderSheet(MACHINING_NIGHT_SHEET, machiningHeadersForShift('Night')),
    reorderSheet(MACHINING_REJECTIONS_SHEET, machiningRejectionHeaders()),
    reorderSheet(CONFIG_SHEET, CONFIG_HEADERS),
  ];
  Logger.log(log.join('\n'));
}

function reorderSheet(sheetName, desired) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  if (!sheet) return 'SKIP (no such tab): ' + sheetName;

  var current = getHeaders(sheet);
  if (current.length === 0) {
    sheet.getRange(1, 1, 1, desired.length).setValues([desired]);
    sheet.setFrozenRows(1);
    return 'header written: ' + sheetName;
  }

  // Preserve any column this version doesn't know about.
  var finalHeaders = desired.slice();
  current.forEach(function (h) {
    if (h && finalHeaders.indexOf(h) === -1) finalHeaders.push(h);
  });
  if (finalHeaders.join('|') === current.join('|')) {
    applyColumnFormats(sheet, finalHeaders);
    return 'already in order (formats refreshed): ' + sheetName;
  }

  var rows = getAllRowsAsObjects(sheet);
  var out = [finalHeaders];
  rows.forEach(function (r) {
    out.push(finalHeaders.map(function (h) {
      return r[h] === undefined || r[h] === null ? '' : r[h];
    }));
  });

  // Everything is already in memory before anything is cleared.
  sheet.clearContents();
  sheet.getRange(1, 1, out.length, finalHeaders.length).setValues(out);
  sheet.setFrozenRows(1);
  applyColumnFormats(sheet, finalHeaders);
  invalidateCaches();
  return 'reordered ' + sheetName + ' (' + rows.length + ' data rows)';
}

// A cell's number format belongs to its POSITION, not to the data that moves
// through it. So a column that shifts inherits whatever the previous occupant
// was formatted as — RejectionTotal landing where LastUpdated used to sit read
// back as "1900-01-06" instead of 8, because 8 is eight days past the epoch.
//
// Rather than trusting whatever is there, formats are set from the header
// name: percent for the LOR columns, dates for the date columns, and default
// for everything else. Idempotent, so re-running the migration repairs a sheet
// that already went wrong.
function applyColumnFormats(sheet, headers) {
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return;                 // header only, nothing to format
  var n = lastRow - 1;

  headers.forEach(function (header, i) {
    var range = sheet.getRange(2, i + 1, n, 1);
    range.clearFormat();
    if (header.indexOf('LOR') !== -1) {
      range.setNumberFormat('0%');
    } else if (header === 'LastUpdated') {
      range.setNumberFormat('yyyy-mm-dd hh:mm:ss');
    } else if (header === 'Date') {
      range.setNumberFormat('yyyy-mm-dd');
    }
  });
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
  ['MO', 'Barcode', 'PartName'].forEach(function (col) {
    if (getHeaders(configSheet).indexOf(col) === -1) {
      configSheet.getRange(1, configSheet.getLastColumn() + 1).setValue(col);
      log.push('Added Config!' + col + ' column');
    }
  });

  Logger.log(log.join('\n'));
}

// ---------- Helpers ----------

// Every module is now split across two per-shift sheets — use
// getCastingSheetForShift / getSecondarySheetForShift / getMachiningSheetForShift.

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
  // A brand-new/empty tab has lastColumn 0, and getRange(...,0) throws
  // "The number of columns in the range must be at least 1" — report it as
  // "no headers" so callers can raise a message that says what to actually do.
  var lastCol = sheet.getLastColumn();
  if (lastCol < 1) return [];
  return sheet
    .getRange(1, 1, 1, lastCol)
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
