/* ─────────────────────────────────────────────────────────────
   Wiring: filters -> aggregation -> cards.

   Each module gets the charts its sheet can actually answer. Casting
   and Secondary share a shape (output, rate, machine/station, part,
   hour-of-shift). Machining adds what only it records: the good/scrap
   split, defect types, and downtime.

   Filter behaviour follows one rule throughout — a filter that changes
   how many series are on screen must NOT repaint the survivors. Colour
   follows the entity, so a machine keeps its hue whether it is one of
   six or on its own.
   ───────────────────────────────────────────────────────────── */

import {
  CONFIG, loadAll, dateWindow, shortDate, SLOTS, MODULE_LABELS,
  RAW_TABS, sheetUrl,
} from './data.js';
import {
  lineChart, barsH, colsV, donut, legend, table,
  seriesColor, fmtInt, fmtPct, fmtMin,
} from './charts.js';

const state = {
  module: 'casting',
  shift: 'all',
  days: 30,
  group: null,          // null = every machine/station/customer
  operation: null,      // machining only; null = every operation
  rawTab: 'Casting_Day',// which sheet tab the Tables view shows
  rawQuery: '',
  data: null,
};

/** Today, as the sheet dates it. A night shift that runs past midnight is
    still filed under the day it STARTED, which is exactly what the Date
    column already holds — so a plain date match is the right test. */
const todayKey = () => new Date().toISOString().slice(0, 10);

/** Sheet values are inconsistent ("machining " with a space, and legacy
    line names like "FY2" from before operations existed). Match on a
    normalised key, display what the sheet actually says. */
const opKey = (v) => String(v || '').trim().toLowerCase();
const opLabel = (v) => {
  const k = opKey(v);
  if (!k) return 'Unset';
  return k.charAt(0).toUpperCase() + k.slice(1);
};

/* Colour follows the entity: a stable index per group name, decided
   once from the full roster, so filtering never repaints anything. */
const groupIndex = new Map();
function colorForGroup(name) {
  return seriesColor(groupIndex.get(name) ?? 99);
}

const $ = (sel) => document.querySelector(sel);
const view = $('#view');

/* ── Aggregation ────────────────────────────────────────────── */

function rowsFor(module) {
  const bucket = state.data?.[module];
  if (!bucket) return [];
  const rows = state.shift === 'all'
    ? [...bucket.Day, ...bucket.Night]
    : bucket[state.shift];
  const window = new Set(dateWindow(state.days));
  return rows.filter(
    (r) =>
      window.has(r.date) &&
      (!state.group || r.group === state.group) &&
      (!state.operation || opKey(r.operation) === state.operation)
  );
}

function rejectionsFor() {
  const all = state.data?.rejections ?? [];
  const window = new Set(dateWindow(state.days));
  return all.filter(
    (r) =>
      window.has(r.date) &&
      (state.shift === 'all' || r.shift === state.shift) &&
      (!state.group || r.group === state.group) &&
      (!state.operation || opKey(r.operation) === state.operation)
  );
}

const sum = (rows, pick) => rows.reduce((a, r) => a + (pick(r) || 0), 0);

function byDate(rows, pick) {
  const dates = dateWindow(state.days);
  const map = new Map(dates.map((d) => [d, 0]));
  let touched = new Set();
  for (const r of rows) {
    if (!map.has(r.date)) continue;
    map.set(r.date, map.get(r.date) + (pick(r) || 0));
    touched.add(r.date);
  }
  // A day nobody logged is a GAP, not a zero — drawing it as zero
  // invents a shutdown that did not happen.
  return dates.map((d) => (touched.has(d) ? map.get(d) : null));
}

function groupTotals(rows) {
  const map = new Map();
  for (const r of rows) {
    const cur = map.get(r.group) || { actual: 0, plan: 0, rejected: 0, downtime: 0 };
    cur.actual += r.actualTotal;
    cur.plan += r.plan;
    cur.rejected += r.rejected;
    cur.downtime += r.downtimeTotal;
    map.set(r.group, cur);
  }
  return [...map.entries()]
    .map(([group, v]) => ({ group, ...v }))
    .sort((a, b) => b.actual - a.actual);
}

/** A row logged before part numbers were mandatory has a blank PartNo, and
    a bar with no label is unreadable — name it rather than drop it. */
const partLabel = (part) => (part && part.trim()) || '(no part no.)';

function partTotals(rows) {
  const map = new Map();
  for (const r of rows) {
    const key = `${r.part}|||${r.partName}`;
    const cur = map.get(key) || { part: partLabel(r.part), name: r.partName, actual: 0, rejected: 0, groups: new Set() };
    cur.actual += r.actualTotal;
    cur.rejected += r.rejected;
    cur.groups.add(r.group);
    map.set(key, cur);
  }
  return [...map.values()].sort((a, b) => b.actual - a.actual);
}

/** The checkpoints on screen. With both shifts showing that is all eleven
    in running order — anything less quietly drops a shift's output while
    the card still calls itself a total. */
function checkpoints() {
  if (state.shift === 'Day') return SLOTS.Day;
  if (state.shift === 'Night') return SLOTS.Night;
  return [...SLOTS.Day, ...SLOTS.Night];
}

/** Where in the shift the output actually comes from. */
function hourProfile(rows) {
  const slots = checkpoints();
  const map = new Map(slots.map((s) => [s, 0]));
  for (const r of rows) {
    for (const s of r.slots) {
      if (map.has(s.slot)) map.set(s.slot, map.get(s.slot) + (s.actual || 0));
    }
  }
  return slots.map((slot) => ({ label: slot, value: map.get(slot) }));
}

function downtimeByHour(rows) {
  const slots = checkpoints();
  const map = new Map(slots.map((s) => [s, 0]));
  for (const r of rows) {
    for (const s of r.slots) {
      if (map.has(s.slot)) map.set(s.slot, map.get(s.slot) + (s.downtime || 0));
    }
  }
  return slots.map((slot) => ({ label: slot, value: map.get(slot) }));
}

/** Top 5 defect types plus Other — never a 9th generated hue. */
function defectTotals(rejections) {
  const map = new Map();
  for (const r of rejections) map.set(r.type, (map.get(r.type) || 0) + r.qty);
  const sorted = [...map.entries()]
    .map(([type, qty]) => ({ type, qty }))
    .sort((a, b) => b.qty - a.qty);
  if (sorted.length <= 6) return sorted;
  const head = sorted.slice(0, 5);
  const other = sorted.slice(5).reduce((a, d) => a + d.qty, 0);
  return [...head, { type: 'Other', qty: other, isOther: true }];
}

/* ── Card helpers ───────────────────────────────────────────── */

function card({ title, sub, span = 6, body = '', id }) {
  return `
    <section class="card col-${span}">
      <div class="card-head">
        <div>
          <div class="card-title">${title}</div>
          ${sub ? `<div class="card-sub">${sub}</div>` : ''}
        </div>
        ${id ? `<div class="card-actions"><button class="mini-toggle" data-twin="${id}">Table</button></div>` : ''}
      </div>
      ${body}
    </section>`;
}

function plot(id) {
  return `<div class="chart-wrap" id="${id}"></div>
          <div class="hidden" id="${id}-twin"></div>`;
}

function kpi(label, value, unit, note, noteClass = '') {
  return `
    <section class="card kpi">
      <div class="kpi-label">${label}</div>
      <div class="kpi-value tnum">${value}${unit ? `<span class="kpi-unit"> ${unit}</span>` : ''}</div>
      ${note ? `<div class="kpi-note ${noteClass}">${note}</div>` : ''}
    </section>`;
}

/* ── Render ─────────────────────────────────────────────────── */

function render() {
  const isTables = state.module === 'tables';
  $('#analysisFilters').hidden = isTables;
  $('#tableFilters').hidden = !isTables;
  if (isTables) { renderTables(); return; }

  const module = state.module;
  const labels = MODULE_LABELS[module];
  const rows = rowsFor(module);
  const dates = dateWindow(state.days);
  const axis = dates.map(shortDate);

  $('#groupFilterLabel').textContent = labels.group;

  if (!rows.length) {
    view.innerHTML = `<section class="card"><div class="empty">
      Nothing logged for ${labels.title}${state.group ? ` · ${state.group}` : ''}
      in the last ${state.days} days${state.shift === 'all' ? '' : ` on the ${state.shift} shift`}.
    </div></section>`;
    return;
  }

  const totalActual = sum(rows, (r) => r.actualTotal);
  const totalPlan = sum(rows, (r) => r.plan);
  const attainment = totalPlan ? (totalActual / totalPlan) * 100 : null;
  const groups = groupTotals(rows);
  const parts = partTotals(rows);
  const activeDays = new Set(rows.map((r) => r.date)).size;

  /* KPI strip — hero numbers, no plot, so no hover layer. */
  let kpis =
    kpi('Total actual', fmtInt(totalActual), 'pcs',
        `${activeDays} day${activeDays === 1 ? '' : 's'} with production`) +
    kpi('Plan attainment', attainment === null ? '—' : fmtPct(attainment), '',
        `${fmtInt(totalPlan)} planned`,
        attainment !== null && attainment >= 100 ? 'good' : '') +
    kpi(`${labels.group}s running`, fmtInt(groups.length), '',
        groups.length ? `Top: ${groups[0].group}` : '');

  if (module === 'machining') {
    const totalRejected = sum(rows, (r) => r.rejected);
    const good = Math.max(0, totalActual - totalRejected);
    const rejectRate = totalActual ? (totalRejected / totalActual) * 100 : 0;
    const downtime = sum(rows, (r) => r.downtimeTotal);
    kpis =
      kpi('Total actual', fmtInt(totalActual), 'pcs',
          `${activeDays} day${activeDays === 1 ? '' : 's'} with production`) +
      kpi('Good parts', fmtInt(good), 'pcs', `${fmtPct(100 - rejectRate)} of actual`, 'good') +
      kpi('Rejected', fmtInt(totalRejected), 'pcs', `${fmtPct(rejectRate)} rejection rate`,
          rejectRate > 10 ? 'critical' : '') +
      kpi('Downtime', fmtInt(downtime), 'min',
          downtime
            ? `${fmtInt(Math.round(downtime / Math.max(1, activeDays)))} min per production day`
            : 'none recorded') +
      kpi('Plan attainment', attainment === null ? '—' : fmtPct(attainment), '',
          `${fmtInt(totalPlan)} planned`,
          attainment !== null && attainment >= 100 ? 'good' : '');
  }

  const cards = [];

  /* Output over time — one series when a group is picked, otherwise
     Day vs Night so the shift comparison is always one glance away. */
  const bothShifts = state.shift === 'all';
  cards.push(card({
    title: 'Output over time',
    sub: bothShifts ? 'Day and Night, per day' : `${state.shift} shift, per day`,
    span: bothShifts ? 6 : 8,
    id: 'trend',
    body: plot('trend'),
  }));

  cards.push(card({
    title: 'Where the shift produces',
    sub: bothShifts
      ? 'Total by checkpoint — day shift, then night'
      : `Total by checkpoint, ${state.shift.toLowerCase()} shift`,
    span: bothShifts ? 6 : 4,
    id: 'hours',
    body: plot('hours'),
  }));

  cards.push(card({
    title: `Output by ${labels.group.toLowerCase()}`,
    sub: `${groups.length} ${labels.groupPlural} in this window`,
    span: 6,
    id: 'groups',
    body: plot('groups'),
  }));

  cards.push(card({
    title: 'Output by part',
    sub: `${parts.length} parts`,
    span: 6,
    id: 'parts',
    body: plot('parts'),
  }));

  if (module === 'machining' && !state.operation) {
    cards.push(card({
      title: 'Machining vs assembly',
      sub: 'The two halves of the department, side by side',
      span: 12, id: 'ops', body: plot('ops'),
    }));
  }

  if (module === 'machining') {
    cards.push(card({
      title: 'Good vs rejected',
      sub: 'Of everything produced',
      span: 4, id: 'split', body: plot('split'),
    }));
    cards.push(card({
      title: 'Defects by type',
      sub: 'Top 5 and the rest folded into Other',
      span: 8, id: 'defects', body: plot('defects'),
    }));
    cards.push(card({
      title: 'Worst rejection rate by part',
      sub: 'Parts under 50 pieces are left out — a rate off a tiny run is noise',
      span: 6, id: 'scrap', body: plot('scrap'),
    }));
    cards.push(card({
      title: 'Downtime by hour',
      sub: 'Minutes lost across the window',
      span: 6, id: 'downtime', body: plot('downtime'),
    }));
  }

  cards.push(card({
    title: 'Daily figures',
    sub: 'The numbers behind the charts',
    span: 12,
    body: `<div id="daily"></div>`,
  }));

  view.innerHTML =
    `<div class="kpis">${kpis}</div>` +
    liveCard(module, labels) +
    `<div class="grid">${cards.join('')}</div>`;

  drawTrend(module, axis, dates);
  drawHours(rows);
  drawGroups(groups, labels);
  drawParts(parts);
  if (module === 'machining' && !state.operation) drawOperations(rows);
  if (module === 'machining') {
    drawSplit(rows);
    drawDefects();
    drawScrap(parts);
    drawDowntime(rows);
  }
  drawDaily(module, rows, dates);
  wireTwins();
}

function drawTrend(module, axis, dates) {
  const host = $('#trend');
  const bucket = state.data[module];
  const window = new Set(dates);
  const pick = (arr) =>
    arr.filter((r) => window.has(r.date) && (!state.group || r.group === state.group));

  let series;
  if (state.shift === 'all') {
    series = [
      { name: 'Day', values: byDate(pick(bucket.Day), (r) => r.actualTotal), color: seriesColor(0) },
      { name: 'Night', values: byDate(pick(bucket.Night), (r) => r.actualTotal), color: seriesColor(6) },
    ];
  } else {
    series = [{
      name: `${state.shift} output`,
      values: byDate(pick(bucket[state.shift]), (r) => r.actualTotal),
      color: seriesColor(0),
    }];
  }

  lineChart(host, { labels: axis, series, height: 250 });

  if (series.length > 1) {
    host.insertAdjacentHTML('afterend',
      legend(series.map((s) => ({ label: s.name, color: s.color }))));
  }

  $('#trend-twin').innerHTML = table(
    ['Date', ...series.map((s) => s.name)],
    dates.map((d, i) => [
      d, ...series.map((s) => (s.values[i] === null ? '—' : fmtInt(s.values[i]))),
    ]).reverse()
  );
}

function drawHours(rows) {
  const items = hourProfile(rows).map((d) => ({ ...d, valueLabel: 'Output' }));
  colsV($('#hours'), { items, height: 250, color: seriesColor(0) });
  $('#hours-twin').innerHTML = table(
    ['Checkpoint', 'Output'],
    items.map((d) => [d.label, fmtInt(d.value)])
  );
}

function drawGroups(groups, labels) {
  const items = groups.slice(0, 10).map((g) => ({
    label: g.group,
    value: g.actual,
    valueLabel: 'Output',
    extra: g.plan ? [{ label: 'Attainment', value: fmtPct((g.actual / g.plan) * 100) }] : [],
  }));
  barsH($('#groups'), { items, colorFor: (d) => colorForGroup(d.label) });
  $('#groups-twin').innerHTML = table(
    [labels.group, 'Output', 'Plan', 'Attainment'],
    groups.map((g) => [
      `<span class="swatch" style="background:${colorForGroup(g.group)}"></span>${g.group}`,
      fmtInt(g.actual), fmtInt(g.plan),
      g.plan ? fmtPct((g.actual / g.plan) * 100) : '—',
    ])
  );
}

function drawParts(parts) {
  const items = parts.slice(0, 10).map((p, i) => ({
    label: partLabel(p.part),
    value: p.actual,
    valueLabel: 'Output',
    extra: p.name ? [{ label: 'Name', value: p.name.slice(0, 28) }] : [],
  }));
  // One hue for a one-measure ranking: the entities are ordered here, not
  // identified by colour, so eight hues would be decoration.
  barsH($('#parts'), { items, colorFor: () => seriesColor(6) });
  $('#parts-twin').innerHTML = table(
    ['Part', 'Name', 'Output'],
    parts.map((p) => [partLabel(p.part), p.name || '—', fmtInt(p.actual)])
  );
}

function drawSplit(rows) {
  const actual = sum(rows, (r) => r.actualTotal);
  const rejected = sum(rows, (r) => r.rejected);
  const good = Math.max(0, actual - rejected);
  donut($('#split'), {
    segments: [
      { label: 'Good', value: good, color: 'var(--series-3)' },
      { label: 'Rejected', value: rejected, color: 'var(--series-8)' },
    ],
    centerValue: fmtInt(actual),
    centerLabel: 'actual pcs',
    height: 230,
  });
  $('#split').insertAdjacentHTML('afterend', legend([
    { label: 'Good', color: 'var(--series-3)' },
    { label: 'Rejected', color: 'var(--series-8)' },
  ]));
  $('#split-twin').innerHTML = table(
    ['', 'Pieces', 'Share'],
    [
      ['Good', fmtInt(good), actual ? fmtPct((good / actual) * 100) : '—'],
      ['Rejected', fmtInt(rejected), actual ? fmtPct((rejected / actual) * 100) : '—'],
      ['Total actual', fmtInt(actual), '100%'],
    ]
  );
}

function drawDefects() {
  const defects = defectTotals(rejectionsFor());
  const items = defects.map((d, i) => ({
    label: d.type,
    value: d.qty,
    valueLabel: 'Pieces',
  }));
  const colorFor = (d, i) =>
    d.label === 'Other' ? 'var(--series-other)' : seriesColor(i);
  barsH($('#defects'), { items, colorFor });
  $('#defects-twin').innerHTML = table(
    ['Defect', 'Pieces'],
    defects.map((d, i) => [
      `<span class="swatch" style="background:${colorFor({ label: d.type }, i)}"></span>${d.type}`,
      fmtInt(d.qty),
    ])
  );
}

function drawScrap(parts) {
  const MIN_PIECES = 50;
  const rated = parts
    .filter((p) => p.actual >= MIN_PIECES)
    .map((p) => ({
      label: partLabel(p.part),
      value: (p.rejected / p.actual) * 100,
      valueLabel: 'Rejection rate',
      extra: [
        { label: 'Rejected', value: fmtInt(p.rejected) },
        { label: 'Of actual', value: fmtInt(p.actual) },
      ],
    }))
    .sort((a, b) => b.value - a.value)
    .slice(0, 8);

  if (!rated.length) {
    $('#scrap').innerHTML =
      `<div class="empty">No part reached ${MIN_PIECES} pieces in this window.</div>`;
    return;
  }
  barsH($('#scrap'), { items: rated, format: fmtPct, colorFor: () => 'var(--series-8)' });
  $('#scrap-twin').innerHTML = table(
    ['Part', 'Rejected', 'Of actual', 'Rate'],
    rated.map((r) => [
      r.label, r.extra[0].value, r.extra[1].value, fmtPct(r.value),
    ])
  );
}

function drawDowntime(rows) {
  const items = downtimeByHour(rows).map((d) => ({ ...d, valueLabel: 'Downtime' }));
  const total = items.reduce((a, d) => a + d.value, 0);
  if (!total) {
    $('#downtime').innerHTML = '<div class="empty">No downtime recorded in this window.</div>';
    $('#downtime-twin').innerHTML = '';
    return;
  }
  colsV($('#downtime'), { items, height: 230, format: fmtMin, color: 'var(--series-4)' });
  $('#downtime-twin').innerHTML = table(
    ['Checkpoint', 'Minutes'],
    items.map((d) => [d.label, fmtInt(d.value)])
  );
}

function drawDaily(module, rows, dates) {
  const map = new Map();
  for (const r of rows) {
    const cur = map.get(r.date) || { actual: 0, plan: 0, rejected: 0, downtime: 0 };
    cur.actual += r.actualTotal;
    cur.plan += r.plan;
    cur.rejected += r.rejected;
    cur.downtime += r.downtimeTotal;
    map.set(r.date, cur);
  }
  const rowsOut = dates
    .filter((d) => map.has(d))
    .reverse()
    .map((d) => {
      const v = map.get(d);
      const base = [
        d, fmtInt(v.actual), fmtInt(v.plan),
        v.plan ? fmtPct((v.actual / v.plan) * 100) : '—',
      ];
      return module === 'machining'
        ? [...base, fmtInt(v.rejected),
           v.actual ? fmtPct((v.rejected / v.actual) * 100) : '—',
           fmtInt(v.downtime)]
        : base;
    });

  const cols = module === 'machining'
    ? ['Date', 'Actual', 'Plan', 'Attainment', 'Rejected', 'Rejection %', 'Downtime (min)']
    : ['Date', 'Actual', 'Plan', 'Attainment'];
  $('#daily').innerHTML = table(cols, rowsOut);
}

/* Every chart carries its table twin — the numbers, and the relief the
   sub-3:1 light-mode hues require. */
function wireTwins() {
  view.querySelectorAll('[data-twin]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const id = btn.dataset.twin;
      const plotEl = document.getElementById(id);
      const twin = document.getElementById(`${id}-twin`);
      if (!plotEl || !twin) return;
      const showTable = twin.classList.contains('hidden');
      twin.classList.toggle('hidden', !showTable);
      plotEl.classList.toggle('hidden', showTable);
      const lg = plotEl.nextElementSibling;
      if (lg && lg.classList.contains('legend')) lg.classList.toggle('hidden', showTable);
      btn.textContent = showTable ? 'Chart' : 'Table';
    });
  });
}

/* ── "Running today" ─────────────────────────────────────────────
   Only rows dated today. This is the band a supervisor watches during
   the shift, so it lists every live job rather than summarising them. */
function liveCard(module, labels) {
  const today = todayKey();
  const bucket = state.data[module];
  const rows = [...bucket.Day, ...bucket.Night].filter(
    (r) =>
      r.date === today &&
      (!state.group || r.group === state.group) &&
      (!state.operation || opKey(r.operation) === state.operation) &&
      (state.shift === 'all' || r.shift === state.shift)
  );

  const head = `
    <div class="card-head live-head">
      <span class="live-dot"></span>
      <div>
        <div class="card-title">Running today</div>
        <div class="card-sub">${today} — only what is on the floor now</div>
      </div>
      ${rows.length ? `<div class="card-actions"><span class="live-count">${rows.length} job${rows.length === 1 ? '' : 's'}</span></div>` : ''}
    </div>`;

  if (!rows.length) {
    return `<section class="card live-card" style="margin-bottom:16px">${head}
      <div class="empty">Nothing logged today yet${state.group ? ` for ${state.group}` : ''}.</div>
    </section>`;
  }

  rows.sort((a, b) => b.actualTotal - a.actualTotal);

  const cols = module === 'machining'
    ? [labels.group, 'Operation', 'Part', 'Shift', 'Plan', 'Actual', 'Progress', 'Rejected', 'Downtime', 'Last hour']
    : [labels.group, 'Part', 'Shift', 'Plan', 'Actual', 'Progress', 'Last hour'];

  const body = rows.map((r) => {
    const pct = r.plan ? (r.actualTotal / r.plan) * 100 : null;
    // Status wears an icon as well as a colour — never colour alone.
    const pill = pct === null
      ? '<span class="pill idle">—</span>'
      : pct >= 100
        ? `<span class="pill done">✓ ${fmtPct(pct)}</span>`
        : `<span class="pill ${pct < 50 ? 'behind' : 'idle'}">${fmtPct(pct)}</span>`;
    const filled = r.slots.filter((s) => s.actual !== null);
    const lastHour = filled.length ? filled[filled.length - 1].slot : '—';
    const base = [
      r.group,
      ...(module === 'machining' ? [opLabel(r.operation)] : []),
      partLabel(r.part),
      r.shift,
      fmtInt(r.plan),
      fmtInt(r.actualTotal),
      pill,
    ];
    return module === 'machining'
      ? [...base, fmtInt(r.rejected), r.downtimeTotal ? fmtMin(r.downtimeTotal) : '—', lastHour]
      : [...base, lastHour];
  });

  return `<section class="card live-card" style="margin-bottom:16px">${head}${table(cols, body)}</section>`;
}

/* Machining and assembly are different work on the same parts, so they get
   compared rather than blended — that is the whole point of the split. */
function drawOperations(rows) {
  const map = new Map();
  for (const r of rows) {
    const key = opKey(r.operation);
    const cur = map.get(key) || { label: opLabel(r.operation), actual: 0, rejected: 0, plan: 0, downtime: 0 };
    cur.actual += r.actualTotal;
    cur.rejected += r.rejected;
    cur.plan += r.plan;
    cur.downtime += r.downtimeTotal;
    map.set(key, cur);
  }
  const ops = [...map.values()].sort((a, b) => b.actual - a.actual);
  if (!ops.length) {
    $('#ops').innerHTML = '<div class="empty">No operations recorded in this window.</div>';
    return;
  }

  const items = ops.map((o) => ({
    label: o.label,
    value: o.actual,
    valueLabel: 'Actual',
    extra: [
      { label: 'Rejected', value: fmtInt(o.rejected) },
      { label: 'Rejection rate', value: o.actual ? fmtPct((o.rejected / o.actual) * 100) : '—' },
      { label: 'Downtime', value: fmtMin(o.downtime) },
    ],
  }));
  // Colour follows the operation, fixed by name, so adding a third never
  // repaints the first two.
  const order = ['machining', 'assembly'];
  const colorFor = (d) => {
    const i = order.indexOf(opKey(d.label));
    return i >= 0 ? seriesColor(i) : 'var(--series-other)';
  };
  barsH($('#ops'), { items, colorFor, rowHeight: 38 });

  $('#ops-twin').innerHTML = table(
    ['Operation', 'Actual', 'Plan', 'Attainment', 'Rejected', 'Rejection %', 'Downtime (min)'],
    ops.map((o) => [
      `<span class="swatch" style="background:${colorFor({ label: o.label })}"></span>${o.label}`,
      fmtInt(o.actual), fmtInt(o.plan),
      o.plan ? fmtPct((o.actual / o.plan) * 100) : '—',
      fmtInt(o.rejected),
      o.actual ? fmtPct((o.rejected / o.actual) * 100) : '—',
      fmtInt(o.downtime),
    ])
  );
}

/** Operation chips are built from what the sheet actually contains, so a
    legacy value (an old line name like "FY2") stays reachable instead of
    disappearing between two hardcoded buttons. */
function buildOperationFilter() {
  const seg = $('#opSeg');
  const label = $('#opFilterLabel');
  if (state.module !== 'machining') {
    seg.hidden = true; label.hidden = true;
    state.operation = null;
    return;
  }
  const bucket = state.data.machining;
  const keys = [...new Set(
    [...bucket.Day, ...bucket.Night].map((r) => opKey(r.operation)).filter(Boolean)
  )].sort((a, b) => {
    const order = ['machining', 'assembly'];
    const ia = order.indexOf(a), ib = order.indexOf(b);
    return (ia < 0 ? 9 : ia) - (ib < 0 ? 9 : ib) || a.localeCompare(b);
  });

  seg.hidden = false; label.hidden = false;
  seg.innerHTML =
    `<button data-op="" aria-pressed="${state.operation === null}">All</button>` +
    keys.map((k) => `<button data-op="${k}" aria-pressed="${state.operation === k}">${opLabel(k)}</button>`).join('');

  seg.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.operation = btn.dataset.op || null;
      seg.querySelectorAll('button').forEach((b) =>
        b.setAttribute('aria-pressed', String((b.dataset.op || null) === state.operation)));
      render();
    });
  });
}

/* -- Tables: the sheet as it is ----------------------------------
   Every column, in the sheet's own order, unaggregated. This is the view
   for checking one specific row rather than reading a trend.

   Values come from the RAW cell, not its displayed text. Several columns
   in this spreadsheet carry a number format left behind by whatever used
   to occupy their position, so the sheet itself shows Plan 300 as
   "30000%" and RejectionTotal 16 as a 1900 date. What is printed here is
   what the cell MEANS. */
const IDENTIFIER_COLS = new Set([
  'DCM', 'Station', 'Customer', 'PartNo', 'MO', 'Barcode', 'Operation',
  'RejectionCode', 'Shift', 'Hour', 'EmployeeID',
]);

function rawCell(col, value) {
  if (value === '' || value === null || value === undefined) {
    return { text: '\u2014', cls: 'blank' };
  }
  const str = String(value);

  // gviz hands dates back as Date(y,m,d[,h,mi,s]).
  const d = str.match(/^Date\((\d+),(\d+),(\d+)(?:,(\d+),(\d+),(\d+))?/);
  if (d) {
    const y = d[1], mo = d[2], day = d[3], h = d[4], mi = d[5];
    const date = y + '-' + String(+mo + 1).padStart(2, '0') + '-' +
      String(+day).padStart(2, '0');
    return h !== undefined
      ? { text: date + ' ' + h.padStart(2, '0') + ':' + mi.padStart(2, '0'), cls: '' }
      : { text: date, cls: '' };
  }

  if (typeof value === 'number') {
    // LOR columns are stored as a fraction; show the percentage they mean.
    if (/^LOR_/.test(col)) {
      return { text: (value * 100).toFixed(2) + '%', cls: 'num' };
    }
    // A machine or part number is an IDENTIFIER that happens to be digits.
    // Grouping it turns DCM 1212 into "1,212" and part 2244 into "2,244",
    // which is not what is in the sheet and not what anyone searches for.
    if (IDENTIFIER_COLS.has(col)) {
      return { text: String(value), cls: '' };
    }
    const rounded = Math.round(value * 1000) / 1000;
    return { text: rounded.toLocaleString('en-US'), cls: 'num' };
  }
  return { text: str, cls: '' };
}

function buildTableChips() {
  const chips = $('#tableChips');
  chips.innerHTML = RAW_TABS.map((t) => {
    const n = state.data && state.data.raw && state.data.raw[t.name]
      ? state.data.raw[t.name].rows.length : undefined;
    const count = n === undefined ? '' : ' (' + n + ')';
    const label = t.shift === 'Both' ? t.label : t.label + ' \u00b7 ' + t.shift;
    return '<button class="chip" data-tab="' + t.name + '" aria-pressed="' +
      (state.rawTab === t.name) + '">' + label + count + '</button>';
  }).join('');

  chips.querySelectorAll('.chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      state.rawTab = chip.dataset.tab;
      chips.querySelectorAll('.chip').forEach((c) =>
        c.setAttribute('aria-pressed', String(c.dataset.tab === state.rawTab)));
      renderTables();
    });
  });
}

function renderTables() {
  buildTableChips();
  const raw = state.data && state.data.raw ? state.data.raw[state.rawTab] : null;
  const meta = RAW_TABS.find((t) => t.name === state.rawTab);
  const link = sheetUrl();

  if (!raw) {
    view.innerHTML = '<section class="card"><div class="empty">' +
      (state.data && state.data.mode === 'sample'
        ? 'Connect the spreadsheet to see its tables \u2014 this view has no sample.'
        : 'Could not read the ' + state.rawTab + ' tab.') +
      '</div></section>';
    return;
  }

  const q = state.rawQuery.trim().toLowerCase();
  const rows = q
    ? raw.rows.filter((r) =>
        raw.cols.some((c) => String(r[c] === undefined ? '' : r[c]).toLowerCase().includes(q)))
    : raw.rows;

  const head = raw.cols.map((c) => '<th>' + c + '</th>').join('');
  const body = rows.map((r) => {
    const cells = raw.cols.map((c) => {
      const cell = rawCell(c, r[c]);
      return '<td class="' + cell.cls + '">' + cell.text + '</td>';
    }).join('');
    return '<tr>' + cells + '</tr>';
  }).join('');

  const shiftNote = meta && meta.shift !== 'Both' ? ' \u00b7 ' + meta.shift + ' shift' : '';
  const linkNote = link
    ? ' \u00b7 <a href="' + link + '" target="_blank" rel="noopener" style="color:var(--brand)">open in Sheets</a>'
    : '';

  view.innerHTML =
    '<section class="card">' +
      '<div class="card-head"><div>' +
        '<div class="card-title">' + state.rawTab + '</div>' +
        '<div class="card-sub">' + rows.length + ' of ' + raw.rows.length +
          ' row' + (raw.rows.length === 1 ? '' : 's') + ' \u00b7 ' +
          raw.cols.length + ' columns' + shiftNote + linkNote +
        '</div>' +
      '</div></div>' +
      (rows.length
        ? '<div class="raw-wrap"><table class="raw"><thead><tr>' + head +
          '</tr></thead><tbody>' + body + '</tbody></table></div>'
        : '<div class="empty">No row matches that filter.</div>') +
    '</section>';
}

/* ── Chrome ─────────────────────────────────────────────────── */

function buildGroupChips() {
  const bucket = state.data[state.module];
  if (!bucket) return;                 // the Tables tab has no group roster
  const names = [...new Set([...bucket.Day, ...bucket.Night].map((r) => r.group))]
    .filter(Boolean)
    .sort();

  groupIndex.clear();
  names.forEach((n, i) => groupIndex.set(n, i));

  const chips = $('#groupChips');
  chips.innerHTML =
    `<button class="chip" data-group="" aria-pressed="${state.group === null}">All</button>` +
    names.map((n) => `<button class="chip" data-group="${n}" aria-pressed="${state.group === n}">${n}</button>`).join('');

  chips.querySelectorAll('.chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      state.group = chip.dataset.group || null;
      chips.querySelectorAll('.chip').forEach((c) =>
        c.setAttribute('aria-pressed', String((c.dataset.group || null) === state.group)));
      render();
    });
  });
}

function setBanner(kind, html) {
  const banner = $('#banner');
  if (!kind) { banner.hidden = true; return; }
  banner.hidden = false;
  $('#bannerInner').className = `banner-inner ${kind}`;
  $('#bannerInner').innerHTML = html;
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('hicom-dash-theme', theme);
  $('#themeIcon').innerHTML = theme === 'dark'
    ? '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>'
    : '<circle cx="12" cy="12" r="4.5"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>';
}

async function boot() {
  applyTheme(
    localStorage.getItem('hicom-dash-theme') ||
    (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
  );

  $('#themeBtn').addEventListener('click', () => {
    const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    render();                      // charts read their colours from CSS vars
  });

  $('#moduleTabs').querySelectorAll('.tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      state.module = tab.dataset.module;
      state.group = null;
      $('#moduleTabs').querySelectorAll('.tab').forEach((t) =>
        t.setAttribute('aria-selected', String(t === tab)));
      if (state.module !== 'tables') {
        buildGroupChips();
        buildOperationFilter();
      }
      render();
    });
  });

  let searchTimer;
  $('#tableSearch').addEventListener('input', (ev) => {
    // Debounced: a tab can run to thousands of rows and every keystroke
    // would otherwise rebuild the whole table.
    clearTimeout(searchTimer);
    const value = ev.target.value;
    searchTimer = setTimeout(() => {
      state.rawQuery = value;
      renderTables();
    }, 180);
  });

  const segs = [
    ['#shiftSeg', 'shift', (b) => b.dataset.shift],
    ['#rangeSeg', 'days', (b) => Number(b.dataset.days)],
  ];
  for (const [sel, key, read] of segs) {
    $(sel).querySelectorAll('button').forEach((btn) => {
      btn.addEventListener('click', () => {
        state[key] = read(btn);
        $(sel).querySelectorAll('button').forEach((b) =>
          b.setAttribute('aria-pressed', String(b === btn)));
        render();
      });
    });
  }

  $('#refreshBtn').addEventListener('click', load);

  // Billed as live, so it refreshes itself. Two minutes is well inside the
  // gap between checkpoints and nowhere near any quota.
  setInterval(() => {
    if (document.visibilityState === 'visible') load({ quiet: true });
  }, 120000);

  await load();
}

async function load({ quiet = false } = {}) {
  if (!quiet) view.innerHTML =
    `<div class="kpis">${'<section class="card skeleton" style="height:96px"></section>'.repeat(4)}</div>
     <div class="grid">
       <section class="card skeleton col-8" style="height:300px"></section>
       <section class="card skeleton col-4" style="height:300px"></section>
     </div>`;
  try {
    state.data = await loadAll();
    const stamp = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    $('#dataSource').textContent = state.data.mode === 'sheet'
      ? `live from the production sheet · updated ${stamp}`
      : 'sample data — sheet not connected yet';
    if (state.data.mode === 'sample') {
      setBanner('warn',
        `<div><b>Showing sample data.</b> The layout and every calculation are real —
         only the numbers are stand-ins. To go live, paste your spreadsheet id into
         <code>js/data.js</code>, share the file as “anyone with the link can view”,
         and set <code>source: 'sheet'</code>.</div>`);
    } else {
      setBanner(null);
    }
    if (state.module !== 'tables') {
      buildGroupChips();
      buildOperationFilter();
    }
    render();
  } catch (err) {
    $('#dataSource').textContent = 'could not read the sheet';
    setBanner('err', `<div><b>Could not load the sheet.</b> ${err.message}</div>`);
    view.innerHTML = '';
  }
}

boot();
