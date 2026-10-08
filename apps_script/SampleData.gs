// ---------- Sample data: a week of made-up shifts to try the system on ----------
//
// Add this as a SECOND script file next to Code.gs (Apps Script editor → + →
// Script → name it SampleData), save, then pick a function in the toolbar and
// press Run. Nothing here is reachable from the web app — only from the editor.
//
//   seedSampleData()   fills every configured part, in all three modules, for
//                      both shifts, from SAMPLE_FROM up to SAMPLE_UNTIL.
//   clearSampleData()  removes every row this file wrote, and only those.
//
// Every sample row is signed "Sample data" in LoggedBy, which is how
// clearSampleData() finds them again. A row someone has already logged for real
// is never touched: that part/shift/day is skipped, so seeding into a sheet that
// is already in use only fills the gaps. Each seed first clears the previous
// sample and writes it again, so moving SAMPLE_UNTIL later and re-running fills
// the checkpoints that have passed since. Values come from a fixed seed per
// row, so a row whose checkpoints have not changed gets the same numbers again.
// Edits made by hand to a sample row are replaced on re-seed.

var SAMPLE_FROM = '2026-10-01';
// Checkpoints after this moment are left blank, the way a shift still in
// progress would look. At noon on 8 Oct: the night of the 7th is complete
// (12AM, 4AM, 7:30AM) and the Day shift of the 8th has its 12PM checkpoint.
var SAMPLE_UNTIL = '2026-10-08 12:00';
var SAMPLE_BY = 'Sample data';

// Clock time of each checkpoint, as minutes from the shift date's midnight.
// Night checkpoints fall on the next calendar day, hence the extra 24h.
var SAMPLE_SLOT_MINUTES = {
  '12PM': 12 * 60, '4PM': 16 * 60, '7_30PM': 19 * 60 + 30,
  '12AM': 24 * 60, '4AM': 28 * 60, '7_30AM': 31 * 60 + 30,
};

function seedSampleData() {
  var tz = Session.getScriptTimeZone();
  var until = Utilities.parseDate(SAMPLE_UNTIL, tz, 'yyyy-MM-dd HH:mm');
  var dates = sampleDates_(tz, until);
  // Start from a clean slate, so rows written by an earlier, shorter run get
  // the checkpoints that have passed since instead of being skipped as taken.
  var report = [clearSampleData()];

  ['Day', 'Night'].forEach(function (shift) {
    report.push(seedFlatModule_('casting', 'DCM', getCastingSheetForShift(shift),
      shift, dates, until, tz, [200, 500]));
    report.push(seedFlatModule_('secondary', 'Station', getSecondarySheetForShift(shift),
      shift, dates, until, tz, [300, 700]));
    report.push(seedMachining_(shift, dates, until, tz));
  });

  invalidateCaches();
  var text = report.join('\n');
  Logger.log(text);
  return text;
}

function clearSampleData() {
  var report = [];
  var removedMachiningKeys = {};
  [CASTING_DAY_SHEET, CASTING_NIGHT_SHEET, SECONDARY_DAY_SHEET, SECONDARY_NIGHT_SHEET,
    MACHINING_DAY_SHEET, MACHINING_NIGHT_SHEET].forEach(function (name) {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(name);
    if (!sheet) return;
    var shift = /Night$/.test(name) ? 'Night' : 'Day';
    var isMachining = name.indexOf('Machining') === 0;
    var removed = rewriteWithout_(sheet, function (row) {
      var sample = isSampleRow_(row);
      if (sample && isMachining) {
        removedMachiningKeys[sampleRejectionKey_(formatDateOnly(row.Date), shift,
          row.Customer, row.PartNo, row.Operation)] = true;
      }
      return sample;
    });
    report.push(name + ': removed ' + removed + ' sample rows');
  });

  // Defects live in their own tab with no LoggedBy, so they go with the
  // machining row they were filed under.
  var rej = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(MACHINING_REJECTIONS_SHEET);
  if (rej) {
    var removedRej = rewriteWithout_(rej, function (row) {
      return removedMachiningKeys[sampleRejectionKey_(formatDateOnly(row.Date), row.Shift,
        row.Customer, row.PartNo, row.Operation)] === true;
    });
    report.push(MACHINING_REJECTIONS_SHEET + ': removed ' + removedRej + ' sample defect lines');
  }

  invalidateCaches();
  var text = report.join('\n');
  Logger.log(text);
  return text;
}

// ---------- Casting and Secondary: same shape, different group column ----------

function seedFlatModule_(module, groupCol, sheet, shift, dates, until, tz, planRange) {
  var headers = getHeaders(sheet);
  var existing = getAllRowsAsObjects(sheet);
  var slots = slotsForShift(shift);
  var out = [];

  getConfigGroups(module).forEach(function (group) {
    getConfigParts(module, group).forEach(function (part) {
      var info = getConfigPartInfo(module, group, part);
      dates.forEach(function (date) {
        var taken = existing.some(function (r) {
          return String(r[groupCol]) === group && String(r.PartNo) === part &&
            formatDateOnly(r.Date) === date;
        });
        if (taken) return;
        var rnd = sampleRandom_([module, shift, group, part, date].join('|'));
        var row = { Date: date, PartNo: part, MO: info.mo, Report: info.report,
          Barcode: info.barcode, PartName: info.name };
        row[groupCol] = group;
        if (!fillShift_(row, slots, date, until, tz, rnd, planRange)) return;
        out.push(headers.map(function (h) { return row.hasOwnProperty(h) ? row[h] : ''; }));
      });
    });
  });

  appendRows_(sheet, out, headers, null);
  return sheet.getName() + ': added ' + out.length + ' rows';
}

// ---------- Machining: plus operation, line, downtime and defects ----------

function seedMachining_(shift, dates, until, tz) {
  var sheet = getMachiningSheetForShift(shift);
  var headers = getHeaders(sheet);
  var existing = getAllRowsAsObjects(sheet);
  var slots = slotsForShift(shift);
  var reasons = readDowntimeReasons();
  var types = getRejectionTypes();
  types = types.status === 'success' ? types.data : [];
  var rejSheet = requireSheet(MACHINING_REJECTIONS_SHEET, 'setupMachiningShiftSheets');
  var rejHeaders = getHeaders(rejSheet);
  var out = [];
  var rejOut = [];

  getConfigGroups('machining').forEach(function (customer) {
    getConfigOperations().forEach(function (operation) {
      getConfigPartEntries('machining', customer, operation).forEach(function (entry) {
        var info = getConfigPartInfo('machining', customer, entry.part, operation,
          entry.lineName, entry.lineNo);
        dates.forEach(function (date) {
          var taken = existing.some(function (r) {
            return String(r.Customer) === customer && String(r.PartNo) === entry.part &&
              String(r.Operation) === operation && matchesLine(r, entry.lineName, entry.lineNo) &&
              formatDateOnly(r.Date) === date;
          });
          if (taken) return;
          var rnd = sampleRandom_(['machining', shift, customer, operation, entry.part,
            entry.lineNo, date].join('|'));
          var row = { Date: date, Customer: customer, PartNo: entry.part, Operation: operation,
            WorkCenter: entry.lineNo, Name: entry.lineName, MO: info.mo, Report: info.report,
            Barcode: info.barcode, PartName: info.name };
          var logged = fillShift_(row, slots, date, until, tz, rnd, [300, 900]);
          if (!logged) return;

          var defects = [];
          logged.forEach(function (slot) {
            // About one checkpoint in four has a stoppage worth writing down.
            if (rnd() < 0.25) {
              row['Downtime_' + slot] = 5 * (2 + Math.floor(rnd() * 11)); // 10–60 min
              row['DowntimeReason_' + slot] = reasons.length
                ? reasons[Math.floor(rnd() * reasons.length)].label : '';
            }
            // Most checkpoints find a defect or two; a few are clean.
            var count = rnd() < 0.3 ? 0 : (rnd() < 0.7 ? 1 : 2);
            for (var i = 0; i < count && types.length; i++) {
              var t = types[Math.floor(rnd() * types.length)];
              if (defects.some(function (d) { return d.slot === slot && d.type === t.type; })) continue;
              defects.push({ code: t.code, type: t.type, qty: 1 + Math.floor(rnd() * 8), slot: slot });
            }
          });

          var rejected = summariseRejections(defects);
          row.RejectionTotal = rejected.total;
          row.RejectionSummary = rejected.summary;
          var downtime = summariseDowntime(row, slots);
          row.DowntimeTotal = downtime.total;
          row.DowntimeSummary = downtime.summary;
          row.GoodTotal = row.ActualTotal - rejected.total;
          out.push(headers.map(function (h) { return row.hasOwnProperty(h) ? row[h] : ''; }));

          defects.forEach(function (d) {
            var line = { Date: date, Shift: shift, Customer: customer, PartNo: entry.part,
              Operation: operation, Barcode: info.barcode, PartName: info.name, MO: info.mo,
              Report: info.report, RejectionCode: padRejectionCode(d.code), RejectionType: d.type,
              Qty: d.qty, LastUpdated: row.LastUpdated, Hour: d.slot };
            rejOut.push(rejHeaders.map(function (h) { return line.hasOwnProperty(h) ? line[h] : ''; }));
          });
        });
      });
    });
  });

  appendRows_(sheet, out, headers, null);
  appendRows_(rejSheet, rejOut, rejHeaders, 'Hour');
  return sheet.getName() + ': added ' + out.length + ' rows, ' + rejOut.length + ' defect lines';
}

// ---------- Shared pieces ----------

// Plan, the checkpoints that have already passed, their running LOR, and who
// "logged" them. Returns the slots filled, or null when none had passed yet.
function fillShift_(row, slots, date, until, tz, rnd, planRange) {
  var midnight = Utilities.parseDate(date + ' 00:00', tz, 'yyyy-MM-dd HH:mm').getTime();
  var due = slots.filter(function (slot) {
    return midnight + SAMPLE_SLOT_MINUTES[slot] * 60000 <= until.getTime();
  });
  if (!due.length) return null;

  var plan = 50 * Math.round((planRange[0] + rnd() * (planRange[1] - planRange[0])) / 50);
  row.Plan = plan;
  var meta = {};
  var lastAt = null;
  due.forEach(function (slot) {
    // Each checkpoint is a third of the plan, give or take: most shifts land
    // near it, some fall well short, a few beat it.
    var pace = 0.7 + rnd() * 0.42;
    row['Actual_' + slot] = Math.round((plan / slots.length) * pace);
    lastAt = new Date(midnight + (SAMPLE_SLOT_MINUTES[slot] + 2 + Math.floor(rnd() * 12)) * 60000);
    meta[slot] = { by: SAMPLE_BY, at: Utilities.formatDate(lastAt, tz, 'HH:mm') };
  });
  row.ActualTotal = deriveCumulativeLor(row, slots, 'Actual_', 'LOR_');
  row.LogMeta = JSON.stringify(meta);
  row.LoggedBy = due.map(function (slot) { return SAMPLE_BY + ' ' + slot; }).join(' · ');
  row.LastUpdated = lastAt;
  return due;
}

function sampleDates_(tz, until) {
  var dates = [];
  var day = Utilities.parseDate(SAMPLE_FROM + ' 12:00', tz, 'yyyy-MM-dd HH:mm');
  while (day.getTime() <= until.getTime()) {
    dates.push(Utilities.formatDate(day, tz, 'yyyy-MM-dd'));
    day = new Date(day.getTime() + 24 * 60 * 60 * 1000);
  }
  return dates;
}

// One write per tab instead of one per row. [textCol] is forced to plain text
// first: "12PM" in the defects' Hour column would otherwise be turned into a
// clock time by Sheets (see writeMachiningRejections).
function appendRows_(sheet, rows, headers, textCol) {
  if (!rows.length) return;
  var start = sheet.getLastRow() + 1;
  if (textCol) {
    var col = headers.indexOf(textCol) + 1;
    if (col > 0) sheet.getRange(start, col, rows.length, 1).setNumberFormat('@');
  }
  sheet.getRange(start, 1, rows.length, headers.length).setValues(rows);
}

// Rewrites a tab's data block without the rows [drop] picks, in one pass —
// deleting hundreds of rows one at a time would run past the script time limit.
function rewriteWithout_(sheet, drop) {
  var rows = getAllRowsAsObjects(sheet);
  if (!rows.length) return 0;
  var headers = getHeaders(sheet);
  var keep = [];
  var removed = 0;
  rows.forEach(function (row) {
    if (drop(row)) { removed++; return; }
    keep.push(headers.map(function (h) { return row[h]; }));
  });
  if (!removed) return 0;
  sheet.getRange(2, 1, rows.length, headers.length).clearContent();
  if (keep.length) {
    var hourCol = headers.indexOf('Hour') + 1;
    if (hourCol > 0) sheet.getRange(2, hourCol, keep.length, 1).setNumberFormat('@');
    sheet.getRange(2, 1, keep.length, headers.length).setValues(keep);
  }
  return removed;
}

// A sample row is one every checkpoint of which was first logged by the
// sample. An hour someone logs on top of it later is still theirs to keep,
// so a row with any real entry in it stays.
function isSampleRow_(row) {
  var meta;
  try {
    meta = row.LogMeta ? JSON.parse(row.LogMeta) : null;
  } catch (e) {
    return false;
  }
  if (!meta) return false;
  var slots = Object.keys(meta);
  return slots.length > 0 && slots.every(function (slot) {
    return meta[slot] && meta[slot].by === SAMPLE_BY;
  });
}

function sampleRejectionKey_(date, shift, customer, part, operation) {
  return [date, shift, customer, part, operation].join('|');
}

// A small seeded generator (mulberry32), so each row's numbers depend only on
// which row it is.
function sampleRandom_(key) {
  var h = 1779033703 ^ key.length;
  for (var i = 0; i < key.length; i++) {
    h = Math.imul(h ^ key.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  var a = h >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) | 0;
    var t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
