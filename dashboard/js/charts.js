/* ─────────────────────────────────────────────────────────────
   Chart primitives — plain SVG, no library.

   House rules applied throughout:
     · thin marks; 2px lines; 4px rounded data-ends on bars
     · a 2px surface gap between adjacent/stacked fills
     · recessive grid and axes; selective direct labels only
     · every plot gets a hover layer (crosshair on lines, per-mark
       on bars/segments) — a static chart is the exception, not the rule
     · one y-axis, ever. Two measures of different scale = two charts.

   Charts render at real device pixels (measured host width, redrawn on
   resize) rather than a scaled viewBox, so labels stay crisp and never
   inherit the chart's aspect ratio.
   ───────────────────────────────────────────────────────────── */

const SVG_NS = 'http://www.w3.org/2000/svg';

export const SERIES_VARS = [
  '--series-1', '--series-2', '--series-3', '--series-4',
  '--series-5', '--series-6', '--series-7', '--series-8',
];

/** Fixed-order categorical slot. Never cycled: a 9th entity folds to Other. */
export function seriesColor(i) {
  return i < SERIES_VARS.length
    ? `var(${SERIES_VARS[i]})`
    : 'var(--series-other)';
}

const el = (name, attrs = {}) => {
  const node = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs)) {
    if (v !== null && v !== undefined) node.setAttribute(k, String(v));
  }
  return node;
};

export const fmtInt = (n) =>
  (Math.round(n) || 0).toLocaleString('en-US');

export const fmtPct = (n) =>
  n === null || n === undefined || Number.isNaN(n)
    ? '—'
    : `${(Math.round(n * 10) / 10).toLocaleString('en-US')}%`;

export const fmtMin = (n) => `${fmtInt(n)} min`;

/** A coarse ladder wastes half the plot: 105 should not ceiling at 200. */
function niceMax(value) {
  if (!(value > 0)) return 1;
  const pow = Math.pow(10, Math.floor(Math.log10(value)));
  const norm = value / pow;
  const step = [1, 1.5, 2, 3, 4, 5, 7.5, 10].find((s) => norm <= s) ?? 10;
  return step * pow;
}

function ticks(max, count = 4) {
  const out = [];
  for (let i = 0; i <= count; i++) out.push((max / count) * i);
  return out;
}

/** Tooltip element shared by every chart in a host. */
function ensureTip(host) {
  let tip = host.querySelector(':scope > .tip');
  if (!tip) {
    tip = document.createElement('div');
    tip.className = 'tip';
    host.appendChild(tip);
  }
  return tip;
}

function placeTip(host, tip, x, y) {
  const hostRect = host.getBoundingClientRect();
  const w = tip.offsetWidth;
  const h = tip.offsetHeight;
  // Keep it inside the card: flip before it would overhang.
  let left = x + 14;
  if (left + w > hostRect.width) left = x - w - 14;
  if (left < 0) left = 0;
  let top = y - h - 12;
  if (top < 0) top = y + 16;
  tip.style.left = `${left}px`;
  tip.style.top = `${top}px`;
}

function tipRows(rows) {
  return rows
    .map(
      (r) =>
        `<div class="tip-row">${
          r.color ? `<span class="tip-dot" style="background:${r.color}"></span>` : ''
        }<span>${r.label}</span><b>${r.value}</b></div>`
    )
    .join('');
}

/** Re-render on width change; charts are laid out in real pixels. */
function autosize(host, draw) {
  const run = () => {
    const width = host.clientWidth;
    if (width > 0) draw(width);
  };
  if (host._ro) host._ro.disconnect();
  host._ro = new ResizeObserver(run);
  host._ro.observe(host);
  run();
}

/* ── Line chart ─────────────────────────────────────────────────
   Multi-series over time. Crosshair + shared tooltip; area wash only
   when there is exactly one series (two washes muddy each other).   */
export function lineChart(host, { labels, series, height = 230, format = fmtInt, yLabel }) {
  host.innerHTML = '';
  const tip = ensureTip(host);

  autosize(host, (width) => {
    host.querySelectorAll('svg').forEach((n) => n.remove());
    const pad = { top: 14, right: 16, bottom: 26, left: 46 };
    const w = width;
    const h = height;
    const plotW = Math.max(10, w - pad.left - pad.right);
    const plotH = Math.max(10, h - pad.top - pad.bottom);

    const allValues = series.flatMap((s) => s.values.filter((v) => v !== null));
    const max = niceMax(Math.max(1, ...allValues));
    const n = labels.length;
    const x = (i) => pad.left + (n <= 1 ? plotW / 2 : (plotW * i) / (n - 1));
    const y = (v) => pad.top + plotH - (plotH * v) / max;

    const svg = el('svg', { width: w, height: h, role: 'img' });
    svg.setAttribute('aria-label', yLabel || 'trend');

    // Gridlines + y labels — recessive, hairline.
    for (const t of ticks(max)) {
      svg.appendChild(el('line', {
        x1: pad.left, x2: pad.left + plotW, y1: y(t), y2: y(t),
        stroke: 'var(--gridline)', 'stroke-width': 1,
      }));
      const label = el('text', {
        x: pad.left - 8, y: y(t) + 4, 'text-anchor': 'end',
        fill: 'var(--text-muted)', 'font-size': 10.5,
      });
      label.textContent = format === fmtPct ? `${Math.round(t)}%` : fmtInt(t);
      svg.appendChild(label);
    }

    // X labels: first, last and a couple between — never one per point.
    const labelEvery = Math.max(1, Math.ceil(n / 6));
    labels.forEach((lab, i) => {
      if (i !== 0 && i !== n - 1 && i % labelEvery !== 0) return;
      const t = el('text', {
        x: x(i), y: h - 8,
        'text-anchor': i === 0 ? 'start' : i === n - 1 ? 'end' : 'middle',
        fill: 'var(--text-muted)', 'font-size': 10.5,
      });
      t.textContent = lab;
      svg.appendChild(t);
    });

    const single = series.length === 1;

    series.forEach((s, si) => {
      const color = s.color || seriesColor(si);
      // Break the path at nulls so a day nobody logged is a gap, not a
      // line drawn through zero.
      let d = '';
      let open = false;
      s.values.forEach((v, i) => {
        if (v === null || v === undefined) { open = false; return; }
        d += `${open ? 'L' : 'M'}${x(i)},${y(v)}`;
        open = true;
      });
      if (!d) return;

      if (single) {
        const firstIdx = s.values.findIndex((v) => v !== null);
        const lastIdx = s.values.length - 1 -
          [...s.values].reverse().findIndex((v) => v !== null);
        if (firstIdx >= 0) {
          const area = `${d}L${x(lastIdx)},${pad.top + plotH}L${x(firstIdx)},${pad.top + plotH}Z`;
          svg.appendChild(el('path', { d: area, fill: color, opacity: 0.10 }));
        }
      }

      svg.appendChild(el('path', {
        d, fill: 'none', stroke: color,
        'stroke-width': 2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round',
      }));

      // A day flanked by two blanks draws no segment at all, so it needs a
      // mark of its own or it vanishes from a chart that still counts it.
      s.values.forEach((v, i) => {
        if (v === null || v === undefined) return;
        const before = i > 0 ? s.values[i - 1] : null;
        const after = i < s.values.length - 1 ? s.values[i + 1] : null;
        const isolated = (before === null || before === undefined) &&
                         (after === null || after === undefined);
        if (!isolated) return;
        svg.appendChild(el('circle', {
          cx: x(i), cy: y(v), r: 3.5,
          fill: color, stroke: 'var(--surface)', 'stroke-width': 2,
        }));
      });

      // Direct label at the end of the line — identity without a legend
      // lookup. Only for a handful of series; more than 4 and it crowds.
      if (series.length <= 4) {
        const lastIdx = s.values.length - 1 -
          [...s.values].reverse().findIndex((v) => v !== null);
        if (lastIdx >= 0 && s.values[lastIdx] !== null) {
          svg.appendChild(el('circle', {
            cx: x(lastIdx), cy: y(s.values[lastIdx]), r: 4,
            fill: color, stroke: 'var(--surface)', 'stroke-width': 2,
          }));
        }
      }
    });

    // Hover layer: one crosshair, all series at that x.
    const crosshair = el('line', {
      y1: pad.top, y2: pad.top + plotH,
      stroke: 'var(--axis)', 'stroke-width': 1, opacity: 0,
    });
    svg.appendChild(crosshair);
    const dots = el('g', { opacity: 0 });
    svg.appendChild(dots);

    const hit = el('rect', {
      x: pad.left, y: pad.top, width: plotW, height: plotH,
      fill: 'transparent', style: 'cursor:crosshair',
    });
    svg.appendChild(hit);

    const hide = () => {
      crosshair.setAttribute('opacity', 0);
      dots.setAttribute('opacity', 0);
      tip.dataset.show = 'false';
    };
    hit.addEventListener('pointerleave', hide);
    hit.addEventListener('pointermove', (ev) => {
      const rect = svg.getBoundingClientRect();
      const px = ev.clientX - rect.left;
      const i = n <= 1 ? 0 : Math.round(((px - pad.left) / plotW) * (n - 1));
      const idx = Math.min(n - 1, Math.max(0, i));

      crosshair.setAttribute('x1', x(idx));
      crosshair.setAttribute('x2', x(idx));
      crosshair.setAttribute('opacity', 1);

      dots.innerHTML = '';
      const rows = [];
      series.forEach((s, si) => {
        const v = s.values[idx];
        if (v === null || v === undefined) return;
        const color = s.color || seriesColor(si);
        dots.appendChild(el('circle', {
          cx: x(idx), cy: y(v), r: 4.5,
          fill: color, stroke: 'var(--surface)', 'stroke-width': 2,
        }));
        rows.push({ label: s.name, value: format(v), color });
      });
      dots.setAttribute('opacity', 1);

      if (!rows.length) { tip.dataset.show = 'false'; return; }
      tip.innerHTML = `<div class="tip-title">${labels[idx]}</div>${tipRows(rows)}`;
      tip.dataset.show = 'true';
      placeTip(host, tip, x(idx), ev.clientY - rect.top);
    });

    host.insertBefore(svg, tip);
  });
}

/* ── Horizontal ranked bars ─────────────────────────────────────
   Magnitude across named entities. Value sits at the tip, so the
   sub-3:1 hues never carry the number on their own.                */
export function barsH(host, { items, format = fmtInt, rowHeight = 30, colorFor }) {
  host.innerHTML = '';
  const tip = ensureTip(host);

  autosize(host, (width) => {
    host.querySelectorAll('svg').forEach((n) => n.remove());
    if (!items.length) return;

    const labelW = Math.min(190, Math.max(80, Math.round(width * 0.30)));
    const valueW = 74;
    const pad = { top: 4, right: valueW, bottom: 4, left: labelW };
    const plotW = Math.max(10, width - pad.left - pad.right);
    const h = pad.top + pad.bottom + items.length * rowHeight;
    const max = niceMax(Math.max(1, ...items.map((d) => d.value)));

    const svg = el('svg', { width, height: h, role: 'img' });

    items.forEach((d, i) => {
      const color = colorFor ? colorFor(d, i) : seriesColor(i);
      const barH = Math.min(18, rowHeight - 12);
      const y = pad.top + i * rowHeight + (rowHeight - barH) / 2;
      const w = Math.max(2, (plotW * d.value) / max);

      const name = el('text', {
        x: labelW - 12, y: y + barH / 2 + 4, 'text-anchor': 'end',
        fill: 'var(--text-secondary)', 'font-size': 12,
      });
      name.textContent = d.label.length > 26 ? `${d.label.slice(0, 25)}…` : d.label;
      svg.appendChild(name);

      // Track first, so a short bar still reads as "out of".
      svg.appendChild(el('rect', {
        x: pad.left, y, width: plotW, height: barH,
        rx: 4, fill: 'var(--gridline)', opacity: 0.5,
      }));
      const bar = el('rect', {
        x: pad.left, y, width: w, height: barH,
        rx: 4, fill: color, style: 'cursor:pointer',
      });
      svg.appendChild(bar);

      const val = el('text', {
        x: pad.left + plotW + 10, y: y + barH / 2 + 4,
        fill: 'var(--text-primary)', 'font-size': 12, 'font-weight': 650,
        style: 'font-variant-numeric:tabular-nums',
      });
      val.textContent = format(d.value);
      svg.appendChild(val);

      const show = (ev) => {
        const rect = svg.getBoundingClientRect();
        tip.innerHTML =
          `<div class="tip-title">${d.label}</div>` +
          tipRows([
            { label: d.valueLabel || 'Value', value: format(d.value), color },
            ...(d.extra || []),
          ]);
        tip.dataset.show = 'true';
        placeTip(host, tip, ev.clientX - rect.left, ev.clientY - rect.top);
      };
      bar.addEventListener('pointermove', show);
      bar.addEventListener('pointerleave', () => { tip.dataset.show = 'false'; });
    });

    host.insertBefore(svg, tip);
  });
}

/* ── Vertical columns ───────────────────────────────────────────
   For the hourly profile: few, ordered, comparable categories.      */
export function colsV(host, { items, height = 210, format = fmtInt, color }) {
  host.innerHTML = '';
  const tip = ensureTip(host);

  autosize(host, (width) => {
    host.querySelectorAll('svg').forEach((n) => n.remove());
    if (!items.length) return;

    const pad = { top: 16, right: 8, bottom: 28, left: 44 };
    const plotW = Math.max(10, width - pad.left - pad.right);
    const plotH = Math.max(10, height - pad.top - pad.bottom);
    const max = niceMax(Math.max(1, ...items.map((d) => d.value)));
    const slot = plotW / items.length;
    const barW = Math.min(46, slot - 10);   // the gap between bars is the spacer

    const svg = el('svg', { width, height, role: 'img' });

    for (const t of ticks(max)) {
      const y = pad.top + plotH - (plotH * t) / max;
      svg.appendChild(el('line', {
        x1: pad.left, x2: pad.left + plotW, y1: y, y2: y,
        stroke: 'var(--gridline)', 'stroke-width': 1,
      }));
      const lab = el('text', {
        x: pad.left - 8, y: y + 4, 'text-anchor': 'end',
        fill: 'var(--text-muted)', 'font-size': 10.5,
      });
      lab.textContent = fmtInt(t);
      svg.appendChild(lab);
    }

    items.forEach((d, i) => {
      const x = pad.left + slot * i + (slot - barW) / 2;
      const barH = Math.max(2, (plotH * d.value) / max);
      const y = pad.top + plotH - barH;
      const fill = color || seriesColor(0);

      const bar = el('rect', {
        x, y, width: barW, height: barH, rx: 4,
        fill, style: 'cursor:pointer',
      });
      svg.appendChild(bar);

      // Below ~34px a slot cannot hold "10AM" clear of its neighbour.
      if (i % (slot < 34 ? 2 : 1) === 0) {
        const lab = el('text', {
          x: x + barW / 2, y: height - 9, 'text-anchor': 'middle',
          fill: 'var(--text-muted)', 'font-size': 11,
        });
        lab.textContent = d.label;
        svg.appendChild(lab);
      }

      if (d.value > 0 && slot >= 44) {
        const v = el('text', {
          x: x + barW / 2, y: y - 6, 'text-anchor': 'middle',
          fill: 'var(--text-secondary)', 'font-size': 11, 'font-weight': 650,
          style: 'font-variant-numeric:tabular-nums',
        });
        v.textContent = format(d.value);
        svg.appendChild(v);
      }

      const show = (ev) => {
        const rect = svg.getBoundingClientRect();
        tip.innerHTML = `<div class="tip-title">${d.label}</div>` +
          tipRows([{ label: d.valueLabel || 'Value', value: format(d.value), color: fill }]);
        tip.dataset.show = 'true';
        placeTip(host, tip, ev.clientX - rect.left, ev.clientY - rect.top);
      };
      bar.addEventListener('pointermove', show);
      bar.addEventListener('pointerleave', () => { tip.dataset.show = 'false'; });
    });

    host.insertBefore(svg, tip);
  });
}

/* ── Donut ──────────────────────────────────────────────────────
   Part-to-whole for ONE whole, capped at 5 + Other. A legend is
   always present with the share, so hue never carries it alone.    */
export function donut(host, { segments, centerLabel, centerValue, height = 230 }) {
  host.innerHTML = '';
  const tip = ensureTip(host);

  autosize(host, (width) => {
    host.querySelectorAll('svg').forEach((n) => n.remove());
    const total = segments.reduce((a, s) => a + s.value, 0);
    if (!(total > 0)) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = 'Nothing recorded in this window.';
      host.insertBefore(empty, tip);
      return;
    }

    const size = Math.min(width, height);
    const cx = width / 2;
    const cy = height / 2;
    const r = size / 2 - 8;
    const thickness = Math.max(20, r * 0.34);

    const svg = el('svg', { width, height, role: 'img' });
    // 2px of surface between segments — the gap is what separates two
    // fills, not a lighter shade of one of them.
    const gap = 2 / r;
    let angle = -Math.PI / 2;

    segments.forEach((s, i) => {
      const frac = s.value / total;
      const sweep = frac * Math.PI * 2;
      const a0 = angle + gap / 2;
      const a1 = angle + sweep - gap / 2;
      angle += sweep;
      if (a1 <= a0) return;

      const rOuter = r;
      const rInner = r - thickness;
      const p = (a, rad) => [cx + Math.cos(a) * rad, cy + Math.sin(a) * rad];
      const [x0, y0] = p(a0, rOuter);
      const [x1, y1] = p(a1, rOuter);
      const [x2, y2] = p(a1, rInner);
      const [x3, y3] = p(a0, rInner);
      const large = sweep > Math.PI ? 1 : 0;
      const color = s.color || seriesColor(i);

      const path = el('path', {
        d: `M${x0},${y0}A${rOuter},${rOuter} 0 ${large} 1 ${x1},${y1}` +
           `L${x2},${y2}A${rInner},${rInner} 0 ${large} 0 ${x3},${y3}Z`,
        fill: color, style: 'cursor:pointer',
      });
      svg.appendChild(path);

      const show = (ev) => {
        const rect = svg.getBoundingClientRect();
        tip.innerHTML = `<div class="tip-title">${s.label}</div>` +
          tipRows([
            { label: 'Qty', value: fmtInt(s.value), color },
            { label: 'Share', value: fmtPct(frac * 100) },
          ]);
        tip.dataset.show = 'true';
        placeTip(host, tip, ev.clientX - rect.left, ev.clientY - rect.top);
      };
      path.addEventListener('pointermove', show);
      path.addEventListener('pointerleave', () => { tip.dataset.show = 'false'; });
    });

    const big = el('text', {
      x: cx, y: cy + 2, 'text-anchor': 'middle',
      fill: 'var(--text-primary)', 'font-size': 26, 'font-weight': 800,
      style: 'font-variant-numeric:tabular-nums',
    });
    big.textContent = centerValue ?? fmtInt(total);
    svg.appendChild(big);

    const small = el('text', {
      x: cx, y: cy + 20, 'text-anchor': 'middle',
      fill: 'var(--text-muted)', 'font-size': 11.5,
    });
    small.textContent = centerLabel || '';
    svg.appendChild(small);

    host.insertBefore(svg, tip);
  });
}

/** Legend markup — always rendered for 2+ series. */
export function legend(items) {
  return `<div class="legend">${items
    .map(
      (it) =>
        `<span class="legend-item"><span class="legend-swatch" style="background:${it.color}"></span>${it.label}</span>`
    )
    .join('')}</div>`;
}

/** The table twin every chart carries — numbers, and the contrast relief. */
export function table(columns, rows) {
  const head = columns.map((c) => `<th>${c}</th>`).join('');
  const body = rows
    .map((r) => `<tr>${r.map((cell) => `<td>${cell}</td>`).join('')}</tr>`)
    .join('');
  return `<div class="table-wrap"><table class="data"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}
