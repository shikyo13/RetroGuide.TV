'use strict';

const REFRESH_MS = 60_000;
// The copy is refreshed every minute; older than this means it stopped.
const STALE_MS = 5 * 60_000;
const RANGE_KEY = 'retroguide-stats-days';
const DEFAULT_DAYS = 30;
const PLATFORMS = [
  { key: 'iPhone', label: 'iPhone', color: 'var(--series-1)' },
  { key: 'iPad', label: 'iPad', color: 'var(--series-2)' },
  { key: 'AppleTV', label: 'Apple\u00a0TV', color: 'var(--series-3)' },
  { key: 'Mac', label: 'Mac', color: 'var(--series-4)' },
];
const PLATFORM_NAMES = Object.fromEntries(PLATFORMS.map(p => [p.key, p.label]));
const REASON_GROUPS = {
  playbackFailed: 'Playback failed',
  setupProblem: 'Setup problems',
  setupFailed: 'Setup failed',
  libraryFailed: 'Library failed to load',
};
const REASONS = {
  unreachable: 'Server unreachable', timeout: 'Timed out', offline: 'Device offline', notSecure: 'Not a secure connection',
  certificate: 'Certificate problem', unauthorized: 'Not authorized', serverError: 'Server error', rejected: 'Server refused',
  unreadable: 'Unreadable reply', badAddress: 'Bad address', cancelled: 'Cancelled', interrupted: 'Interrupted',
  noLibraries: 'No libraries', player: 'Player error', didNotStart: 'Picture never started', other: 'Other',
  plexNoServers: 'Plex: no servers on account', plexSignInClosed: 'Plex: sign-in closed', plexCodeExpired: 'Plex: code expired',
  plexLocalNetworkBlocked: 'Plex: local network blocked', plexLocalNetworkRefused: 'Plex: local network refused',
  jellyfinFoundNone: 'Jellyfin: none found', jellyfinFoundNotSecure: 'Jellyfin: found, not secure',
  jellyfinFoundUntrusted: 'Jellyfin: found, untrusted', jellyfinNotSecure: 'Jellyfin: not secure',
  jellyfinNotSecureInternet: 'Jellyfin: not secure (internet)', jellyfinUntrusted: 'Jellyfin: untrusted',
  jellyfinNoAnswer: 'Jellyfin: no answer', jellyfinUnencryptedChosen: 'Jellyfin: chose unencrypted',
  jellyfinLocalNetworkBlocked: 'Jellyfin: local network blocked', jellyfinLocalNetworkRefused: 'Jellyfin: local network refused',
};
const NOT_REPORTED = '—';
const SVG = 'http://www.w3.org/2000/svg';
const CHART = { top: 8, right: 4, bottom: 22, left: 30, gap: 2, radius: 4, ticks: 4, labelSpacing: 56 };

let days = readRange();
let latest = null;

// ---- Small helpers ----------------------------------------------------------

function readRange() {
  try { const v = localStorage.getItem(RANGE_KEY); if (v !== null) return Number(v); } catch { /* storage off */ }
  return DEFAULT_DAYS;
}

function saveRange(value) {
  try { localStorage.setItem(RANGE_KEY, String(value)); } catch { /* storage off */ }
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  // Styles go through the CSSOM: the page's security policy refuses style attributes.
  for (const [k, v] of Object.entries(attrs)) k === 'style' ? (node.style.cssText = v) : node.setAttribute(k, v);
  node.append(...children);
  return node;
}

function svgEl(tag, attrs = {}) {
  const node = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
}

const count = n => new Intl.NumberFormat().format(n);
const price = (amount, currency) => new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount);
/** One rule for every percentage on the page. */
const percent = (part, whole) => (whole ? `${((100 * part) / whole).toFixed(1)}%` : NOT_REPORTED);

function parseDay(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d);
}
const regionNames = new Intl.DisplayNames(undefined, { type: 'region' });
/** A country's name, from its two-letter code; the App Store code if there's no name. */
function countryName(c, missing = NOT_REPORTED) {
  if (!c.country) return missing;
  try { return (c.region && regionNames.of(c.region)) || c.country; } catch { return c.country; }
}
const shortDay = iso => parseDay(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
const clock = date => date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

// ---- Header and headline cards ---------------------------------------------

function renderStatus(data) {
  const asOf = new Date(data.dataAsOf);
  const stale = Date.now() - asOf.getTime() > STALE_MS;
  const status = document.getElementById('status');
  status.className = stale ? 'status stale' : 'status';
  status.textContent = stale
    ? `Data as of ${clock(asOf)}: not updating. Check the copy from the server.`
    : `Data as of ${clock(asOf)} · refreshes every minute`;
  // When the UTC day starts, in the viewer's clock.
  const midnight = new Date(Date.UTC(2000, 0, 1));
  const utcStart = midnight.toLocaleTimeString([], { hour: 'numeric', timeZone: data.timezone });
  document.getElementById('days-note').textContent =
    `Installs and purchases count local days (${data.timezone}). App activity counts UTC days, which start at ${utcStart} local time` +
    (data.activitySince ? `, and has been recorded since ${shortDay(data.activitySince)}.` : '.');
}

function tile(label, value, yesterday, allTime) {
  const compare = el('div', { class: 'compare' },
    el('div', {}, el('span', {}, 'Yesterday'), el('b', {}, yesterday)),
    el('div', {}, el('span', {}, 'All time'), el('b', {}, allTime)));
  return el('div', { class: 'tile' }, el('div', { class: 'label' }, label), el('div', { class: 'value' }, value), compare);
}

function renderTiles(h) {
  const counted = (label, m) => tile(label, count(m.today), count(m.yesterday), count(m.allTime));
  const rate = key => percent(h.purchases[key], h.installs[key]);
  document.getElementById('tiles').replaceChildren(
    counted('Installs', h.installs),
    counted('Purchases', h.purchases),
    tile('Buy rate', rate('today'), rate('yesterday'), rate('allTime')),
    counted('Active devices', h.active),
    counted('Watchers', h.watched),
  );
}

// ---- Charts -----------------------------------------------------------------

function niceMax(value) {
  if (value <= CHART.ticks) return CHART.ticks;
  const step = Math.pow(10, Math.floor(Math.log10(value / CHART.ticks)));
  return [1, 2, 5, 10].map(m => m * step).find(s => s * CHART.ticks >= value) * CHART.ticks;
}

function roundedTop(x, y, w, h, r) {
  if (h <= 0) return '';
  return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
}

/** Stacked (or single) bars per day. A day still in progress is drawn faded;
 *  days before anything was recorded get a band instead of empty bars. */
function barChart(container, rows, series, describe) {
  container.replaceChildren();
  const width = container.clientWidth || 600;
  const height = container.clientHeight || 200;
  const plotW = width - CHART.left - CHART.right;
  const plotH = height - CHART.top - CHART.bottom;
  const totals = rows.map(r => series.reduce((sum, s) => sum + (r[s.key] || 0), 0));
  const max = niceMax(Math.max(1, ...totals));
  const svg = svgEl('svg', { viewBox: `0 0 ${width} ${height}`, role: 'img' });
  const slot = plotW / Math.max(rows.length, 1);
  const barW = Math.max(1, slot - CHART.gap);

  const unrecorded = rows.filter(r => r.recorded === false).length;
  if (unrecorded) {
    svg.append(svgEl('rect', { x: CHART.left, y: CHART.top, width: unrecorded * slot, height: plotH, class: 'unrecorded' }));
    if (unrecorded * slot > 90) {
      const label = svgEl('text', { x: CHART.left + (unrecorded * slot) / 2, y: CHART.top + plotH / 2, 'text-anchor': 'middle' });
      label.textContent = 'Not recorded yet';
      svg.append(label);
    }
  }
  for (let i = 0; i <= CHART.ticks; i++) {
    const value = (max / CHART.ticks) * i;
    const y = CHART.top + plotH - (value / max) * plotH;
    svg.append(svgEl('line', { x1: CHART.left, x2: width - CHART.right, y1: y, y2: y, class: i ? 'gridline' : 'baseline' }));
    const label = svgEl('text', { x: CHART.left - 6, y: y + 4, 'text-anchor': 'end' });
    label.textContent = count(value);
    svg.append(label);
  }
  const labelEvery = Math.ceil(rows.length / Math.max(1, Math.floor(plotW / CHART.labelSpacing)));
  rows.forEach((row, i) => {
    const x = CHART.left + i * slot + CHART.gap / 2;
    let y = CHART.top + plotH;
    const visible = series.filter(s => row[s.key] > 0);
    const group = svgEl('g', row.partial ? { class: 'partial' } : {});
    visible.forEach((s, j) => {
      const h = (row[s.key] / max) * plotH;
      // Stacked segments are separated by a thin surface gap.
      const segment = Math.max(0, h - (j > 0 ? CHART.gap : 0));
      y -= h;
      const r = j === visible.length - 1 ? Math.min(CHART.radius, barW / 2, segment) : 0;
      group.append(svgEl('path', { d: roundedTop(x, y + (h - segment), barW, segment, r), fill: s.color }));
    });
    svg.append(group);
    if ((rows.length - 1 - i) % labelEvery === 0) {
      const label = svgEl('text', { x: x + barW / 2, y: height - 6, 'text-anchor': 'middle' });
      label.textContent = shortDay(row.day);
      svg.append(label);
    }
    const hit = svgEl('rect', { x: CHART.left + i * slot, y: CHART.top, width: slot, height: plotH, class: 'hit' });
    const title = shortDay(row.day) + (row.partial ? ' (so far)' : '');
    const lines = row.recorded === false ? [['Not recorded yet', '']] : describe(row);
    hit.addEventListener('pointermove', e => showTip(e, title, lines));
    hit.addEventListener('pointerleave', hideTip);
    svg.append(hit);
  });
  container.append(svg);
}

function showTip(event, title, lines) {
  const tip = document.getElementById('tooltip');
  tip.replaceChildren(el('div', { class: 't' }, title));
  for (const [label, value, color] of lines) {
    tip.append(el('div', { class: 'r' }, el('span', color ? { style: `--swatch:${color}` } : {}, label), el('b', {}, value)));
  }
  tip.hidden = false;
  const pad = 14;
  const rect = tip.getBoundingClientRect();
  const left = Math.min(event.clientX + pad, window.innerWidth - rect.width - 8);
  const top = event.clientY - rect.height - pad < 8 ? event.clientY + pad : event.clientY - rect.height - pad;
  tip.style.left = `${Math.max(8, left)}px`;
  tip.style.top = `${top}px`;
}

function hideTip() { document.getElementById('tooltip').hidden = true; }

function renderCharts(data) {
  barChart(document.getElementById('installs'), data.daily, [{ key: 'installs', color: 'var(--series-1)' }],
    r => [['Installs', count(r.installs)]]);
  barChart(document.getElementById('purchases'), data.daily, [{ key: 'purchases', color: 'var(--series-1)' }],
    r => [['Purchases', count(r.purchases)], ['Buy rate', percent(r.purchases, r.installs)]]);
  const used = PLATFORMS.filter(p => data.activity.some(r => r[p.key] > 0));
  document.getElementById('activity-legend').replaceChildren(...used.map(p => el('span', { style: `--swatch:${p.color}` }, p.label)));
  barChart(document.getElementById('activity'), data.activity, used,
    r => [...used.slice().reverse().map(p => [p.label, count(r[p.key]), p.color]),
      ['Active devices', count(used.reduce((s, p) => s + r[p.key], 0))], ['Watchers', count(r.watched)]]);
}

function renderFunnel(f) {
  const box = document.getElementById('funnel');
  document.getElementById('funnel-note').textContent = f.since
    ? `Installs first seen since ${shortDay(f.since)} · share of those installs`
    : 'Nothing recorded yet';
  const base = f.steps[0]?.count || 0;
  box.replaceChildren(...f.steps.map((step, i) => {
    const share = base ? (100 * step.count) / base : 0;
    const num = el('div', { class: 'num' }, `${count(step.count)} `, el('small', {}, i ? percent(step.count, base) : ''));
    return el('div', { class: 'row' }, el('div', {}, step.label),
      el('div', { class: 'track' }, el('div', { class: 'bar', style: `width:${share}%` })), num);
  }));
}

// ---- Tables -----------------------------------------------------------------

/** headers: [label, numeric?]; rows: arrays of cells, or { group: title }. */
function table(headers, rows) {
  if (!rows.length) return el('p', { class: 'empty' }, 'Nothing in this range');
  const head = el('tr', {}, ...headers.map(([text, numeric]) => el('th', numeric ? { class: 'n' } : {}, text)));
  const body = rows.map(row => row.group
    ? el('tr', { class: 'group' }, el('td', { colspan: headers.length }, row.group))
    : el('tr', {}, ...row.map((cell, i) => el('td', headers[i][1] ? { class: 'n' } : {}, cell))));
  return el('table', {}, head, ...body);
}

function renderTables(data) {
  const reasons = [];
  for (const [key, title] of Object.entries(REASON_GROUPS)) {
    if (!data.reasons[key]?.length) continue;
    reasons.push({ group: title });
    for (const [reason, devices] of data.reasons[key]) reasons.push([REASONS[reason] || reason, count(devices)]);
  }
  document.getElementById('reasons').replaceChildren(table([['Reason'], ['Devices', true]], reasons));

  const { currencies, free, refunded } = data.sales;
  const left = [free && `${count(free)} free with a code`, refunded && `${count(refunded)} refunded`].filter(Boolean);
  document.getElementById('sales-note').textContent =
    'Price paid, before Apple’s cut; currencies aren’t converted' + (left.length ? ` · not counted: ${left.join(', ')}` : '');
  document.getElementById('sales').replaceChildren(table([['Currency'], ['Purchases', true], ['Sales', true]],
    currencies.map(s => [s.currency, count(s.purchases), price(s.amount, s.currency)])));

  document.getElementById('recent').replaceChildren(table([['When'], ['Device'], ['Country'], ['Price', true]],
    data.recent.map(p => [p.time, PLATFORM_NAMES[p.platform] ?? NOT_REPORTED, countryName(p), price(p.price, p.currency)])));

  document.getElementById('countries').replaceChildren(table([['Country'], ['Installs', true], ['Purchases', true]],
    data.countries.map(c => [countryName(c, 'Not reported'), count(c.installs), count(c.purchases)])));

  document.getElementById('versions').replaceChildren(table([['Version'], ['Devices', true]],
    data.versions.map(v => [v.version, count(v.devices)])));
}

// ---- Loading ----------------------------------------------------------------

function render(data) {
  latest = data;
  renderStatus(data);
  renderTiles(data.headline);
  const first = data.daily[0]?.day;
  document.getElementById('range-note').textContent =
    first ? `Charts and tables below cover ${shortDay(first)} – ${shortDay(data.daily[data.daily.length - 1].day)}` : '';
  renderCharts(data);
  renderFunnel(data.funnel);
  renderTables(data);
}

async function load() {
  document.querySelectorAll('.ranges button').forEach(b => b.setAttribute('aria-pressed', String(Number(b.dataset.days) === days)));
  try {
    const response = await fetch(`data?days=${days}`, { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
  } catch (error) {
    const status = document.getElementById('status');
    status.className = 'status stale';
    status.textContent = `Couldn't refresh (${error.message}). Showing the last numbers.`;
  } finally {
    document.body.classList.remove('loading');
  }
}

document.querySelectorAll('.ranges button').forEach(button => button.addEventListener('click', () => {
  days = Number(button.dataset.days);
  saveRange(days);
  // Keep the current charts, dimmed, until the new range arrives.
  document.body.classList.add('loading');
  load();
}));
let resizeTimer;
window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => latest && render(latest), 150); });
setInterval(load, REFRESH_MS);
load();
