/* ─────────────────────────────────────────────────────────────
   Data layer — reads the production spreadsheet directly.

   Nothing here talks to the Flutter app or its Apps Script backend.
   The sheet IS the source: Day and Night live in separate tabs, so the
   shift filter is a tab choice rather than a derived split — it scopes
   every chart exactly, including per-part and per-defect figures.

   Two adapters:
     SAMPLE  offline figures shaped like the real tabs, so the dashboard
             renders before the sheet is shared. Seeded, not random, so
             the layout doesn't jump between reloads.
     SHEET   the live spreadsheet over Google's gviz endpoint. Needs
             SHEET_ID below and the file shared "anyone with the link
             can view" (gviz sends no credentials).
   ───────────────────────────────────────────────────────────── */

export const CONFIG = {
  /* ── Point this at the real spreadsheet ──────────────────────
     1. Open the sheet. The URL is
        docs.google.com/spreadsheets/d/THIS_PART_HERE/edit
     2. Paste that id below.
     3. Share → General access → "Anyone with the link" → Viewer.
     4. Set source to 'sheet'.
     ──────────────────────────────────────────────────────────── */
  SHEET_ID: '14lBI4kixvt0NOI3fkOQu6ZGvBUgiigJj9SJvCn7opQo',
  source: 'sheet',          // 'sample' | 'sheet'
  windowDays: 14,
};

const TABS = {
  casting:   { Day: 'Casting_Day',   Night: 'Casting_Night',   key: 'DCM' },
  secondary: { Day: 'Secondary_Day', Night: 'Secondary_Night', key: 'Station' },
  machining: { Day: 'Machining_Day', Night: 'Machining_Night', key: 'Customer' },
};
const REJECTIONS_TAB = 'Machining_Rejections';

/** Day lost its 8AM checkpoint (production starts at 10); Night keeps six. */
export const SLOTS = {
  Day:   ['10AM', '12PM', '2PM', '4PM', '6PM'],
  Night: ['8PM', '10PM', '12AM', '2AM', '4AM', '6AM'],
};

/** Every raw tab, in the order the Tables view lists them. */
export const RAW_TABS = [
  { name: 'Casting_Day',        label: 'Casting',   shift: 'Day' },
  { name: 'Casting_Night',      label: 'Casting',   shift: 'Night' },
  { name: 'Secondary_Day',      label: 'Secondary', shift: 'Day' },
  { name: 'Secondary_Night',    label: 'Secondary', shift: 'Night' },
  { name: 'Machining_Day',      label: 'Machining', shift: 'Day' },
  { name: 'Machining_Night',    label: 'Machining', shift: 'Night' },
  { name: 'Machining_Rejections', label: 'Rejections', shift: 'Both' },
];

export const sheetUrl = () =>
  CONFIG.SHEET_ID
    ? `https://docs.google.com/spreadsheets/d/${CONFIG.SHEET_ID}/edit`
    : '';

export const MODULE_LABELS = {
  casting: { title: 'Casting', group: 'Machine', groupPlural: 'machines' },
  secondary: { title: 'Secondary', group: 'Station', groupPlural: 'stations' },
  machining: { title: 'Machining', group: 'Customer', groupPlural: 'customers' },
};

/* ── gviz ──────────────────────────────────────────────────────
   The response is JSONP-ish: a comment, then a call wrapper. Slice to
   the outer braces rather than regex the callback name, which Google
   has changed before.                                                */
/** Column order of the most recent fetchTab call — the raw table view needs
    the sheet's own order, which a plain object cannot preserve reliably. */
let lastCols = [];

async function fetchTab(sheetId, tabName) {
  const url =
    `https://docs.google.com/spreadsheets/d/${sheetId}/gviz/tq` +
    `?tqx=out:json&sheet=${encodeURIComponent(tabName)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${tabName}: HTTP ${res.status}`);
  const text = await res.text();
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end < 0) throw new Error(`${tabName}: unexpected response`);
  const payload = JSON.parse(text.slice(start, end + 1));
  if (payload.status === 'error') {
    const msg = (payload.errors || []).map((e) => e.detailed_message || e.message).join('; ');
    throw new Error(`${tabName}: ${msg || 'query refused'}`);
  }
  const cols = payload.table.cols.map((c) => (c.label || c.id || '').trim());
  lastCols = cols;
  return payload.table.rows.map((r) => {
    const obj = {};
    (r.c || []).forEach((cell, i) => {
      if (!cols[i]) return;
      // Take .v (the RAW value), never .f (what the cell displays).
      // Several columns in the live sheet carry a number format left behind
      // by whatever used to occupy their position, so .f lies:
      //   Plan 300            displays as "30000%"
      //   Actual_12PM 70      displays as "7000.00%"
      //   RejectionTotal 16   displays as "1900-01-15 00:00:00"
      // Reading .f turned that last one into 1900 and invented rejections
      // nobody logged. .v is 300 / 70 / 16 in every one of those cases.
      obj[cols[i]] = cell ? (cell.v !== undefined && cell.v !== null ? cell.v : '') : '';
    });
    return obj;
  });
}

const num = (v) => {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : parseFloat(String(v).replace(/[, %]/g, ''));
  return Number.isFinite(n) ? n : null;
};

/** Sheets hands dates back in several shapes; reduce them all to yyyy-mm-dd. */
function dateKey(value) {
  if (!value) return '';
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  const s = String(value);
  const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (iso) return iso[0];
  const gviz = s.match(/^Date\((\d+),(\d+),(\d+)/);
  if (gviz) {
    const [, y, m, d] = gviz;
    return `${y}-${String(+m + 1).padStart(2, '0')}-${String(+d).padStart(2, '0')}`;
  }
  const parsed = new Date(s);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString().slice(0, 10);
}

/** One production row, normalised so every module reads the same way. */
function normaliseRow(raw, module, shift) {
  const keyCol = TABS[module].key;
  const slots = SLOTS[shift].map((slot) => ({
    slot,
    actual: num(raw[`Actual_${slot}`]),
    // A percent-formatted cell hands back the fraction: 0.2 means 20%.
    // LOR is cumulative and can pass 100%, so only values small enough to
    // be a fraction are scaled — a stray raw 70 stays 70.
    lor: (() => {
      const v = num(raw[`LOR_${slot}`]);
      if (v === null) return null;
      return v <= 3 ? v * 100 : v;
    })(),
    downtime: num(raw[`Downtime_${slot}`]),
  }));

  const actualTotal = slots.reduce((a, s) => a + (s.actual || 0), 0);
  const downtimeTotal = slots.reduce((a, s) => a + (s.downtime || 0), 0);
  const rejected = num(raw.RejectionTotal) || 0;

  return {
    date: dateKey(raw.Date),
    shift,
    // Trim: live rows carry trailing spaces ("machining "), and an untrimmed
    // name splits one machine into two everywhere it is grouped.
    group: String(raw[keyCol] ?? '').trim(),
    part: String(raw.PartNo ?? '').trim(),
    partName: String(raw.PartName ?? '').trim(),
    operation: String(raw.Operation ?? '').trim(),
    mo: String(raw.MO ?? '').trim(),
    plan: num(raw.Plan) || 0,
    slots,
    // ActualTotal/GoodTotal/DowntimeTotal are blank on every row logged
    // before those columns existed, so they are recomputed from the
    // per-checkpoint cells rather than read. RejectionTotal IS filled, and
    // is the row's own count.
    actualTotal,
    rejected,
    good: Math.max(0, actualTotal - rejected),
    downtimeTotal,
  };
}

/* ── Sample data ───────────────────────────────────────────────
   Shaped like the real tabs and seeded off the figures already in the
   sheet, so proportions look like the plant rather than like noise.  */
function mulberry(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const SAMPLE_GROUPS = {
  casting: ['DCM21', 'DCM24', 'DCM27', 'DCM31', 'DCM33', 'WELD'],
  secondary: ['TRIM01', 'TRIM04', 'ROBO02', 'SHOTB-BT', 'FETTLING', 'TUMBLING'],
  machining: ['Mazda', 'Proton', 'Toyota', 'Dpem'],
};
const SAMPLE_PARTS = {
  casting: [['2244', 'BRKT ENGINE LH'], ['2215', 'PIPE CONNECTOR'], ['1145', 'CYLINDER HEAD'], ['2226', 'BRKT L6']],
  secondary: [['P-2244', 'BRKT ENGINE LH'], ['P-2215', 'PIPE CONNECTOR'], ['P-2266', 'CASE CHAIN']],
  machining: [['2244', '2244-MAR-NO2-BRKT-ENGINE-LH-MACH'], ['2215', '2215-MAZ-PIPE-CONNECTOR-ASSY'], ['2214', '2214-MAZ-BRACKET-CAP-LASER-MARKING-MACH'], ['2266', '2266-HON-CASE-ASSY-CHAIN-MACH']],
};
const SAMPLE_DEFECTS = [
  'BULGING', 'CHIP OFF MACH', 'BAR CODE NG', 'ALUMINIUM STUCK-STICK',
  'BLACK SPOT', 'BLOW HOLE', 'CRACK MACH', 'OTHERS MACH',
];

function sampleRows(module, shift, days) {
  const rand = mulberry(
    module.length * 977 + (shift === 'Night' ? 31 : 17)
  );
  const rows = [];
  const groups = SAMPLE_GROUPS[module];
  const parts = SAMPLE_PARTS[module];
  const today = new Date();

  for (let d = days - 1; d >= 0; d--) {
    const day = new Date(today.getTime() - d * 86400000);
    const date = day.toISOString().slice(0, 10);
    const weekend = day.getDay() === 0;
    if (weekend) continue;                       // the plant is quiet on Sundays

    groups.forEach((group, gi) => {
      // Not every machine runs every shift — sparsity is realistic and
      // exercises the "no data" paths.
      if (rand() < 0.18) return;
      const [part, partName] = parts[Math.floor(rand() * parts.length)];
      const plan = [200, 250, 300, 350, 400][Math.floor(rand() * 5)];
      const base = (plan / SLOTS[shift].length) * (0.55 + rand() * 0.6);
      const nightPenalty = shift === 'Night' ? 0.88 : 1;

      const slots = SLOTS[shift].map((slot, si) => {
        const ran = rand() > 0.08;
        const actual = ran ? Math.round(base * nightPenalty * (0.75 + rand() * 0.5)) : null;
        const downtime = module === 'machining' && rand() < 0.28
          ? Math.round(rand() * 40 / 5) * 5
          : (module === 'machining' ? 0 : null);
        return { slot, actual, downtime, lor: null };
      });

      let running = 0;
      slots.forEach((s) => {
        if (s.actual === null) return;
        running += s.actual;
        s.lor = plan ? (running / plan) * 100 : null;
      });

      const actualTotal = slots.reduce((a, s) => a + (s.actual || 0), 0);
      const rejected = module === 'machining'
        ? Math.round(actualTotal * (0.02 + rand() * 0.09))
        : 0;
      const downtimeTotal = slots.reduce((a, s) => a + (s.downtime || 0), 0);

      rows.push({
        date, shift, group, part, partName,
        operation: module === 'machining' ? (gi % 3 === 0 ? 'assembly' : 'machining') : '',
        mo: `MO${1200 + gi}`,
        plan, slots, actualTotal, rejected,
        good: Math.max(0, actualTotal - rejected),
        downtimeTotal,
      });
    });
  }
  return rows;
}

function sampleRejections(machiningRows) {
  const rand = mulberry(4242);
  const out = [];
  for (const row of machiningRows) {
    let left = row.rejected;
    if (!left) continue;
    const count = 1 + Math.floor(rand() * 3);
    for (let i = 0; i < count && left > 0; i++) {
      const qty = i === count - 1 ? left : Math.max(1, Math.round(left * (0.3 + rand() * 0.4)));
      left -= qty;
      const filled = row.slots.filter((s) => s.actual !== null);
      const slot = filled.length
        ? filled[Math.floor(rand() * filled.length)].slot
        : row.slots[0].slot;
      out.push({
        date: row.date, shift: row.shift, group: row.group, part: row.part,
        partName: row.partName, operation: row.operation,
        type: SAMPLE_DEFECTS[Math.floor(rand() * SAMPLE_DEFECTS.length)],
        qty, slot,
      });
    }
  }
  return out;
}

/* ── Public API ─────────────────────────────────────────────── */

/** Every module and shift, normalised. Throws with a readable message. */
export async function loadAll() {
  if (CONFIG.source === 'sheet') {
    if (!CONFIG.SHEET_ID) {
      throw new Error(
        'No SHEET_ID set. Open js/data.js and paste the spreadsheet id, ' +
        'then share the file as "anyone with the link can view".'
      );
    }
    const out = { raw: {} };
    for (const module of Object.keys(TABS)) {
      out[module] = { Day: [], Night: [] };
      for (const shift of ['Day', 'Night']) {
        const tabName = TABS[module][shift];
        const raw = await fetchTab(CONFIG.SHEET_ID, tabName);
        // Keep the sheet's own rows and column order untouched, for the
        // Tables view. The normalised copy below drops most columns.
        out.raw[tabName] = { cols: lastCols.slice(), rows: raw };
        out[module][shift] = raw
          .map((r) => normaliseRow(r, module, shift))
          .filter((r) => r.date && r.group);
      }
    }
    const rawRejections = await fetchTab(CONFIG.SHEET_ID, REJECTIONS_TAB);
    out.raw[REJECTIONS_TAB] = { cols: lastCols.slice(), rows: rawRejections };
    out.rejections = rawRejections
      .map((r) => ({
        date: dateKey(r.Date),
        shift: String(r.Shift ?? '').trim(),
        group: String(r.Customer ?? '').trim(),
        part: String(r.PartNo ?? '').trim(),
        partName: String(r.PartName ?? '').trim(),
        operation: String(r.Operation ?? '').trim(),
        type: String(r.RejectionType ?? '').trim(),
        qty: num(r.Qty) || 0,
        slot: String(r.Hour ?? '').trim(),
      }))
      .filter((r) => r.date && r.type);
    out.mode = 'sheet';
    return out;
  }

  const days = CONFIG.windowDays;
  const out = { mode: 'sample', raw: {} };
  for (const module of Object.keys(TABS)) {
    out[module] = {
      Day: sampleRows(module, 'Day', days),
      Night: sampleRows(module, 'Night', days),
    };
  }
  out.rejections = sampleRejections([
    ...out.machining.Day, ...out.machining.Night,
  ]);
  return out;
}

/** The last N dates, oldest first — the axis, zero-filled. */
export function dateWindow(days) {
  const out = [];
  const today = new Date();
  for (let i = days - 1; i >= 0; i--) {
    out.push(new Date(today.getTime() - i * 86400000).toISOString().slice(0, 10));
  }
  return out;
}

export function shortDate(iso) {
  const [, m, d] = iso.split('-');
  return `${d}/${m}`;
}
