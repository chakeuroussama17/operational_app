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
 *   Module | Kind | Group | Value
 *   - Kind = "group": one row per DCM/Station/Customer. Group = its name,
 *     Value blank. (Lets a group exist with zero parts yet.)
 *   - Kind = "part": one row per part under a group. Group = the parent
 *     DCM/Station/Customer name, Value = the part name.
 *   - Kind = "line": Machining only, global (not per-part). Group blank,
 *     Value = the line name (e.g. "Line 1").
 *   Module is stored lowercase ("casting" | "secondary" | "machining").
 *   Run seedDefaultConfig() once from the Apps Script editor (Run menu)
 *   after creating this tab to populate it with the current defaults.
 *
 * Casting:
 *   Date | DCM | PartNo | Plan |
 *   Output_10AM | Output_LOR10AM | Output_12PM | Output_LOR12PM |
 *   Output_2PM  | Output_LOR2PM  | Output_4PM  | Output_LOR4PM  |
 *   Output_6PM  | Output_LOR6PM  | Output_8PM  | Output_LOR8PM  | LastUpdated
 *
 * Secondary:
 *   Date | Station | PartNo | Plan |
 *   Actual_10AM | LOR_10AM | Actual_12PM | LOR_12PM |
 *   Actual_2PM  | LOR_2PM  | Actual_4PM  | LOR_4PM  |
 *   Actual_6PM  | LOR_6PM  | Actual_8PM  | LOR_8PM  | LastUpdated
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
var CASTING_SHEET = 'Casting';
var SECONDARY_SHEET = 'Secondary';
var MACHINING_SHEET = 'Machining';
var CONFIG_SHEET = 'Config';
var OUTPUT_TIME_SLOTS = ['10AM', '12PM', '2PM', '4PM', '6PM', '8PM'];

// Bump this whenever you redeploy so you can confirm the new code went live:
// open the /exec URL in a browser and check the "version" field.
var BACKEND_VERSION = 'ANALYTICS-v1';

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
    } else {
      if (action === 'dashboard') return jsonResponse(getDashboard(module));
      if (action === 'parts') {
        var key = (module === 'secondary') ? e.parameter.station : e.parameter.dcm;
        return jsonResponse(getParts(module, key));
      }
      if (action === 'row') {
        var key = (module === 'secondary') ? e.parameter.station : e.parameter.dcm;
        return jsonResponse(getRow(module, key, e.parameter.part));
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
    if (payload.action === 'config') return jsonResponse(configMutate(payload));
    if (payload.module === 'casting') return jsonResponse(upsertRow('casting', payload.data));
    if (payload.module === 'secondary') return jsonResponse(upsertRow('secondary', payload.data));
    if (payload.module === 'machining') return jsonResponse(upsertMachiningRow(payload.data));
    return jsonResponse({ status: 'error', message: 'Unknown module' });
  } catch (err) {
    return jsonResponse({ status: 'error', message: err.toString() });
  }
}

// ---------- Reads (Casting & Secondary) ----------

function getDashboard(module) {
  // Casting calls this with no module param at all (it predates Secondary/
  // Machining and was always "the default"), so falsy must mean 'casting'.
  module = module || 'casting';
  var sheet = getModuleSheet(module);
  var rows = getAllRowsAsObjects(sheet);
  var today = getTodayString();
  var groups = getConfigGroups(module);
  var keyName = (module === 'secondary') ? 'Station' : 'DCM';

  var result = groups.map(function (key) {
    var latest = null;
    rows.forEach(function (r) {
      if (String(r[keyName]) === key && formatDateOnly(r.Date) === today && r.LastUpdated) {
        if (!latest || new Date(r.LastUpdated) > new Date(latest)) latest = r.LastUpdated;
      }
    });
    return {
      dcm: key,
      lastUpdated: latest ? hhmm(latest) : null
    };
  });
  return { status: 'success', data: result };
}

function getParts(module, key) {
  module = module || 'casting';
  var sheet = getModuleSheet(module);
  var rows = getAllRowsAsObjects(sheet);
  var today = getTodayString();
  var parts = getConfigParts(module, key);
  var keyName = (module === 'secondary') ? 'Station' : 'DCM';

  var result = parts.map(function (part) {
    var match = rows.find(function (r) {
      return String(r[keyName]) === key && String(r.PartNo) === part && formatDateOnly(r.Date) === today;
    });
    var filled = 0;
    if (match) {
      OUTPUT_TIME_SLOTS.forEach(function (slot) {
        var outputKey = (module === 'secondary') ? 'Actual_' + slot : 'Output_' + slot;
        var v = match[outputKey];
        if (v !== '' && v !== null && v !== undefined) filled++;
      });
    }
    return {
      part: part,
      lastUpdated: match && match.LastUpdated ? hhmm(match.LastUpdated) : null,
      fillPercent: match ? Math.round((filled / OUTPUT_TIME_SLOTS.length) * 100) : 0,
    };
  });
  return { status: 'success', data: result };
}

function getRow(module, key, part) {
  var sheet = getModuleSheet(module);
  var rows = getAllRowsAsObjects(sheet);
  var today = getTodayString();
  var keyName = (module === 'secondary') ? 'Station' : 'DCM';

  var match = rows.find(function (r) {
    return String(r[keyName]) === key && String(r.PartNo) === part && formatDateOnly(r.Date) === today;
  });
  if (!match) return { status: 'success', data: null };
  delete match._rowNum;
  return { status: 'success', data: match };
}

// ---------- Upsert (Casting & Secondary) ----------

function upsertRow(module, data) {
  var sheet = getModuleSheet(module);
  var headers = getHeaders(sheet);
  var rows = getAllRowsAsObjects(sheet);
  var today = getTodayString();
  var keyName = (module === 'secondary') ? 'Station' : 'DCM';

  var existing = rows.find(function (r) {
    return String(r[keyName]) === String(data[keyName]) &&
      String(r.PartNo) === String(data.PartNo) &&
      formatDateOnly(r.Date) === today;
  });

  var merged = existing ? Object.assign({}, existing) : {};
  merged.Date = today;
  merged[keyName] = data[keyName];
  merged.PartNo = data.PartNo;
  if (data.Plan !== undefined && data.Plan !== '') merged.Plan = data.Plan;

  OUTPUT_TIME_SLOTS.forEach(function (slot) {
    var outKey = (module === 'secondary') ? 'Actual_' + slot : 'Output_' + slot;
    var lorKey = (module === 'secondary') ? 'LOR_' + slot : 'Output_LOR' + slot;
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

  var sheet = getModuleSheet(module);
  var rows = getAllRowsAsObjects(sheet);
  var tz = Session.getScriptTimeZone();

  var dateKeys = [];
  var today = new Date();
  for (var i = days - 1; i >= 0; i--) {
    var d = new Date(today.getTime() - i * 24 * 60 * 60 * 1000);
    dateKeys.push(Utilities.formatDate(d, tz, 'yyyy-MM-dd'));
  }

  var outputPrefix = (module === 'secondary') ? 'Actual_' : 'Output_';
  var lorPrefix = (module === 'secondary') ? 'LOR_' : 'Output_LOR';
  var outputKeys = OUTPUT_TIME_SLOTS.map(function (s) { return outputPrefix + s; });
  var lorKeys = OUTPUT_TIME_SLOTS.map(function (s) { return lorPrefix + s; });
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

// ---------- Helpers ----------

function getModuleSheet(module) {
  var sheetName = (module === 'secondary') ? SECONDARY_SHEET :
    (module === 'machining') ? MACHINING_SHEET : CASTING_SHEET;
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  if (!sheet) throw new Error(sheetName + ' sheet tab not found');
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
