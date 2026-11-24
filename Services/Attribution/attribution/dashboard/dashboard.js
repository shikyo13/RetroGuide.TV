'use strict';

const REFRESH_MS = 60_000;
// The copy is refreshed every minute; older than this means it stopped.
const STALE_MS = 5 * 60_000;
const RANGE_KEY = 'retroguide-stats-days';
const PLATFORMS = [
  { key: 'iPhone', label: 'iPhone', color: 'var(--series-1)' },
  { key: 'iPad', label: 'iPad', color: 'var(--series-2)' },
  { key: 'AppleTV', label: 'Apple TV', color: 'var(--series-3)' },
  { key: 'Mac', label: 'Mac', color: 'var(--series-4)' },
];
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
const SVG = 'http://www.w3.org/2000/svg';
const CHART = { top: 8, right: 4, bottom: 22, left: 30, gap: 2, radius: 4, ticks: 4 };

let days = readRange();
let latest = null;

function readRange() {
  try { const v = localStorage.getItem(RANGE_KEY); if (v !== null) return Number(v); } catch { /* private mode */ }
  return 30;
}

function saveRange(value) {
  try { localStorage.setItem(RANGE_KEY, String(value)); } catch { /* private mode */ }
}

function el(tag, attrs = {}, text) {
  const node = document.createElement(tag);
  // Styles go through the CSSOM: the page's security policy refuses style attributes.
  for (const [k, v] of Object.entries(attrs)) k === 'style' ? (node.style.cssText = v) : node.setAttribute(k, v);
  if (text !== undefined) node.textContent = text;
  return node;
}

function svgEl(tag, attrs = {}) {
  const node = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
}

const number = new Intl.NumberFormat();
function money(revenue) {
  const entries = Object.entries(revenue || {});
  if (!entries.length) return '—';
  return entries.map(([currency, amount]) =>
    new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount)).join(' + ');
}
function shortDay(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function niceMax(value) {
  if (value <= CHART.ticks) return CHART.ticks;
  const step = Math.pow(10, Math.floor(Math.log10(value / CHART.ticks)));
  const unit = [1, 2, 5, 10].map(m => m * step).find(s => s * CHART.ticks >= value);
  return unit * CHART.ticks;
}

/** Stacked (or single) bars per day, with a per-day hover tooltip. */
function barChart(container, rows, series, describe) {
  container.replaceChildren();
  const width = container.clientWidth || 600;
  const height = container.clientHeight || 200;
  const plotW = width - CHART.left - CHART.right;
  const plotH = height - CHART.top - CHART.bottom;
  const totals = rows.map(r => series.reduce((sum, s) => sum + (r[s.key] || 0), 0));
  const max = niceMax(Math.max(1, ...totals));
  const svg = svgEl('svg', { viewBox: `0 0 ${width} ${height}`, role: 'img' });
  for (let i = 0; i <= CHART.ticks; i++) {
    const value = (max / CHART.ticks) * i;
    const y = CHART.top + plotH - (value / max) * plotH;
    svg.append(svgEl('line', { x1: CHART.left, x2: width - CHART.right, y1: y, y2: y, class: i ? 'gridline' : 'baseline' }));
    const label = svgEl('text', { x: CHART.left - 6, y: y + 4, 'text-anchor': 'end' });
    label.textContent = number.format(value);
    svg.append(label);
  }
  const slot = plotW / Math.max(rows.length, 1);
  const barW = Math.max(1, slot - CHART.gap);
  const labelEvery = Math.ceil(rows.length / Math.max(1, Math.floor(plotW / 56)));
  rows.forEach((row, i) => {
    const x = CHART.left + i * slot + CHART.gap / 2;
    let y = CHART.top + plotH;
    const visible = series.filter(s => row[s.key] > 0);
    visible.forEach((s, j) => {
      const h = (row[s.key] / max) * plotH;
      const top = j === visible.length - 1;
      // Separate stacked segments with a thin surface gap.
      const segment = Math.max(0, h - (j > 0 ? CHART.gap : 0));
      y -= h;
      const r = top ? Math.min(CHART.radius, barW / 2, segment) : 0;
      svg.append(svgEl('path', { d: roundedTop(x, y + (h - segment), barW, segment, r), fill: s.color }));
    });
    if ((rows.length - 1 - i) % labelEvery === 0) {
      const label = svgEl('text', { x: x + barW / 2, y: height - 6, 'text-anchor': 'middle' });
      label.textContent = shortDay(row.day);
      svg.append(label);
    }
    const hit = svgEl('rect', { x: CHART.left + i * slot, y: CHART.top, width: slot, height: plotH, class: 'hit' });
    hit.addEventListener('pointermove', e => showTip(e, shortDay(row.day), describe(row)));
    hit.addEventListener('pointerleave', hideTip);
    svg.append(hit);
  });
  container.append(svg);
}

function roundedTop(x, y, w, h, r) {
  if (h <= 0) return '';
  return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
}

function showTip(event, title, lines) {
  const tip = document.getElementById('tooltip');
  tip.replaceChildren(el('div', { class: 't' }, title));
  for (const [label, value, color] of lines) {
    const row = el('div', { class: 'r' });
    const name = el('span', color ? { style: `--swatch:${color}` } : {}, label);
    row.append(name, el('b', {}, value));
    tip.append(row);
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

function tile(label, value, sub) {
  const node = el('div', { class: 'tile' });
  node.append(el('div', { class: 'label' }, label), el('div', { class: 'value' }, value));
  const subline = el('div', { class: 'sub' });
  subline.innerHTML = sub;
  node.append(subline);
  return node;
}

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function renderTiles(h) {
  const rate = (p, i) => (i ? `${((100 * p) / i).toFixed(1)}%` : '—');
  document.getElementById('tiles').replaceChildren(
    tile('Installs today', number.format(h.today.installs), `Yesterday <b>${h.yesterday.installs}</b>`),
    tile('Purchases today', number.format(h.today.purchases),
      `${h.today.purchases ? escapeHTML(money(h.today.revenue)) + ' · ' : ''}Yesterday <b>${h.yesterday.purchases}</b>` +
        (h.yesterday.purchases ? ` (${escapeHTML(money(h.yesterday.revenue))})` : '')),
    tile('Buy rate yesterday', rate(h.yesterday.purchases, h.yesterday.installs), 'Purchases per install'),
    tile('Devices active today', number.format(h.activeToday), `Yesterday <b>${h.activeYesterday}</b> · UTC day`),
    tile('Watched today', number.format(h.watchedToday), `Yesterday <b>${h.watchedYesterday}</b> · UTC day`),
    tile('All time', `${number.format(h.allTime.purchases)} sold`,
      `${number.format(h.allTime.installs)} installs · ${escapeHTML(money(h.allTime.revenue))}`),
  );
}

function renderFunnel(f) {
  const box = document.getElementById('funnel');
  box.replaceChildren();
  document.getElementById('funnel-note').textContent = f.since
    ? `Installations first seen since ${shortDay(f.since)} (setup steps are recorded from Nov 14)`
    : 'No setup steps recorded yet';
  const base = f.steps[0]?.count || 0;
  for (const step of f.steps) {
    const share = base ? (100 * step.count) / base : 0;
    const row = el('div', { class: 'row' });
    const track = el('div', { class: 'track' });
    track.append(el('div', { class: 'bar', style: `width:${share}%` }));
    const num = el('div', { class: 'num' }, number.format(step.count) + ' ');
    num.append(el('small', {}, `${share.toFixed(share < 10 && share > 0 ? 1 : 0)}%`));
    row.append(el('div', {}, step.label), track, num);
    box.append(row);
  }
}

function table(headers, rows) {
  if (!rows.length) return el('p', { class: 'empty' }, 'Nothing in this range');
  const t = el('table');
  const head = el('tr');
  headers.forEach(([text, numeric]) => head.append(el('th', numeric ? { class: 'n' } : {}, text)));
  t.append(head);
  for (const row of rows) {
    const tr = el('tr', row.group ? { class: 'group' } : {});
    row.cells.forEach((cell, i) => tr.append(el('td', headers[i]?.[1] ? { class: 'n' } : (row.group ? { colspan: headers.length } : {}), cell)));
    t.append(tr);
  }
  return t;
}

function renderReasons(reasons) {
  const rows = [];
  for (const [key, title] of Object.entries(REASON_GROUPS)) {
    if (!reasons[key]?.length) continue;
    rows.push({ group: true, cells: [title] });
    for (const [reason, count] of reasons[key]) rows.push({ cells: [REASONS[reason] || reason, number.format(count)] });
  }
  document.getElementById('reasons').replaceChildren(table([['Reason'], ['Devices', true]], rows));
}

function render(data) {
  latest = data;
  const asOf = new Date(data.dataAsOf);
  const stale = Date.now() - asOf.getTime() > STALE_MS;
  const updated = document.getElementById('updated');
  updated.className = stale ? 'error' : 'muted';
  updated.textContent = `Data as of ${asOf.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}` +
    (stale ? ' (not updating, check the copy from the server)' : ' · refreshes every minute') + ` · days in ${data.timezone}`;
  renderTiles(data.headline);
  barChart(document.getElementById('installs'), data.daily, [{ key: 'installs', color: 'var(--series-1)' }],
    r => [['Installs', number.format(r.installs)], ['Purchases', number.format(r.purchases)]]);
  barChart(document.getElementById('purchases'), data.daily, [{ key: 'purchases', color: 'var(--series-1)' }],
    r => [['Purchases', number.format(r.purchases)], ['Installs', number.format(r.installs)],
      ['Buy rate', r.installs ? `${((100 * r.purchases) / r.installs).toFixed(1)}%` : '—']]);
  const used = PLATFORMS.filter(p => data.active.some(r => r[p.key] > 0));
  document.getElementById('active-legend').replaceChildren(...used.map(p => el('span', { style: `--swatch:${p.color}` }, p.label)));
  barChart(document.getElementById('active'), data.active, used,
    r => [...used.slice().reverse().map(p => [p.label, number.format(r[p.key]), p.color]),
      ['Total', number.format(used.reduce((s, p) => s + r[p.key], 0))], ['Watched something', number.format(r.watched)]]);
  renderFunnel(data.funnel);
  renderReasons(data.reasons);
  document.getElementById('recent').replaceChildren(table([['When'], ['Device'], ['Country'], ['Price', true]],
    data.recent.map(p => ({ cells: [p.time, { AppleTV: 'Apple TV', unknown: '—' }[p.platform] ?? p.platform, p.country,
      new Intl.NumberFormat(undefined, { style: 'currency', currency: p.currency }).format(p.price)] }))));
  document.getElementById('countries').replaceChildren(table([['Country'], ['Installs', true], ['Purchases', true]],
    data.countries.slice(0, 12).map(([c, i, p]) => ({ cells: [c === 'unknown' ? 'Not reported' : c, number.format(i), number.format(p)] }))));
  document.getElementById('versions-note').textContent = data.versions.day ? `Devices active on ${shortDay(data.versions.day)} (UTC)` : '';
  document.getElementById('versions').replaceChildren(table([['Version'], ['Devices', true]],
    data.versions.versions.map(([v, n]) => ({ cells: [v, number.format(n)] }))));
}

async function load() {
  document.querySelectorAll('.ranges button').forEach(b => b.setAttribute('aria-pressed', String(Number(b.dataset.days) === days)));
  try {
    // Built from the origin: a page opened as user:password@host can't fetch relative URLs.
    const url = new URL(`data?days=${days}`, location.origin + location.pathname);
    const response = await fetch(url, { cache: 'no-store', credentials: 'same-origin' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
  } catch (error) {
    const updated = document.getElementById('updated');
    updated.textContent = `Couldn't refresh (${error.message}). Showing the last numbers.`;
    updated.className = 'error';
  }
}

document.querySelectorAll('.ranges button').forEach(button => button.addEventListener('click', () => {
  days = Number(button.dataset.days);
  saveRange(days);
  load();
}));
let resizeTimer;
window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => latest && render(latest), 150); });
setInterval(load, REFRESH_MS);
load();
