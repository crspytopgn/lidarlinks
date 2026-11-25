// The stats page (GET /): one HTML page drawn from stats() (index.js), with no scripts from elsewhere.

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const h1 = (n) => (n >= 100 ? Math.round(n).toLocaleString("en-GB") : (Math.round(n * 10) / 10).toLocaleString("en-GB"));
const hrs = (n) => `${h1(n)} h`;
const mins = (s) => (s < 3600 ? `${Math.round(s / 60)} min` : `${Math.floor(s / 3600)} h ${Math.round((s % 3600) / 60)} min`);

/** Horizontal bars: rows of {label, value, note?}; one hue (one measure). */
function bars(rows, fmt = hrs) {
  if (!rows.length) return `<p class="muted">Nothing yet.</p>`;
  const max = Math.max(1e-9, ...rows.map((r) => r.value));
  return `<div class="bars" role="table">${rows.map((r) => `
    <div class="bar" role="row" title="${esc(r.label)}: ${esc(fmt(r.value))}${r.note ? " · " + esc(r.note) : ""}">
      <span class="bl" role="cell">${esc(r.label)}</span>
      <span class="bt" role="cell"><span class="bf" style="width:${(100 * r.value / max).toFixed(2)}%"></span></span>
      <span class="bv" role="cell">${esc(fmt(r.value))}${r.note ? `<small> ${esc(r.note)}</small>` : ""}</span>
    </div>`).join("")}</div>`;
}

function niceStep(max) {
  const raw = max / 4, p = 10 ** Math.floor(Math.log10(raw));
  return [1, 2, 5, 10].map((m) => m * p).find((s) => s >= raw) || p * 10;
}

/** Hours per day as columns, every day from the first to today so gaps show as gaps. */
function daily(days, now) {
  if (!days.length) return `<p class="muted">Nothing yet.</p>`;
  const map = new Map(days.map((d) => [d.day, d]));
  const all = [];
  for (let d = new Date(days[0].day + "T00:00:00Z"); d <= now; d.setUTCDate(d.getUTCDate() + 1)) {
    const k = d.toISOString().slice(0, 10);
    all.push(map.get(k) || { day: k, hours: 0 });
  }
  const W = 960, H = 220, pad = 28, n = all.length, bw = (W - pad) / n;
  const max = Math.max(1, ...all.map((d) => d.hours));
  const step = niceStep(max), top = Math.ceil(max / step) * step;
  const y = (v) => H - 18 - (v / top) * (H - 30);
  const grid = [];
  for (let v = 0; v <= top + 1e-9; v += step) {
    grid.push(`<line x1="${pad}" x2="${W}" y1="${y(v)}" y2="${y(v)}" class="grid"/><text x="${pad - 4}" y="${y(v) + 4}" class="ax" text-anchor="end">${v}</text>`);
  }
  const cols = all.map((d, i) => {
    const x = pad + i * bw + 1, w = Math.max(1, bw - 2), hgt = y(0) - y(d.hours);
    const label = i % Math.ceil(n / 10) === 0 ? `<text x="${x + w / 2}" y="${H - 4}" class="ax" text-anchor="middle">${d.day.slice(5)}</text>` : "";
    return `<g class="col"><title>${d.day}: ${h1(d.hours)} h</title><rect x="${pad + i * bw}" y="0" width="${bw}" height="${H - 18}" class="hit"/>
      ${d.hours ? `<rect x="${x}" y="${y(d.hours)}" width="${w}" height="${Math.max(0, hgt - 1)}" class="s1" rx="1"/>` : ""}${label}</g>`;
  }).join("");
  return `<svg viewBox="0 0 ${W} ${H}" class="chart" role="img" aria-label="Hours played per day">${grid.join("")}${cols}</svg>`;
}

export function page(s) {
  const t = s.totals;
  const now = new Date(s.generated_at);
  const tiles = [
    ["Hours played, all time", hrs(t.hours)],
    ["Last 7 days", hrs(t.hours_7d)],
    ["Last 30 days", hrs(t.hours_30d)],
    ["Launches", t.runs.toLocaleString("en-GB")],
    ["Launches, last 7 days", t.runs_7d.toLocaleString("en-GB")],
    ["Typical session", t.median_session_secs == null ? "–" : mins(t.median_session_secs)],
  ];
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LidarLinks play time</title><meta name="robots" content="noindex">
<style>
:root{color-scheme:light;--bg:#fcfcfb;--card:#ffffff;--ink:#0b0b0b;--ink2:#52514e;--muted:#8a8984;--line:#e6e5e0;--s1:#2f8a4e}
@media (prefers-color-scheme:dark){:root{color-scheme:dark;--bg:#141413;--card:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--muted:#8f8e86;--line:#2c2c2a;--s1:#4caf6e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:1040px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:0 0 12px}
.muted,small{color:var(--muted)}.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:20px 0}
.tile,.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}.tile b{display:block;font-size:24px;font-weight:600}
.tile span{color:var(--ink2);font-size:13px}.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px;margin-top:12px}
.chart{width:100%;height:auto;display:block}.chart .grid{stroke:var(--line)}.chart .ax{fill:var(--muted);font-size:11px}
.chart .hit{fill:transparent}.chart .col:hover .hit{fill:var(--line);opacity:.5}.s1{fill:var(--s1)}
.bars{display:grid;gap:6px}.bar{display:grid;grid-template-columns:minmax(90px,30%) 1fr auto;gap:10px;align-items:center;font-size:13px}
.bl{color:var(--ink2);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.bt{height:10px}.bf{display:block;height:100%;background:var(--s1);border-radius:0 4px 4px 0;min-width:2px}
.bv{font-variant-numeric:tabular-nums;text-align:right}.bar:hover .bl{color:var(--ink)}
table{width:100%;border-collapse:collapse;font-size:13px}td,th{text-align:left;padding:4px 6px;border-bottom:1px solid var(--line)}th{color:var(--ink2);font-weight:500}
td.n{text-align:right;font-variant-numeric:tabular-nums}details{margin-top:12px}
</style></head><body><main>
<h1>LidarLinks play time</h1>
<p class="muted">Updated ${esc(s.generated_at.slice(0, 16).replace("T", " "))} UTC. Seconds of play, to the second: each launch reports its running total every 5 minutes of play and when the game is paused, put away or closed.
Anonymous: a random id per launch, never saved; no names, rounds or addresses.</p>
<div class="tiles">${tiles.map(([k, v]) => `<div class="tile"><b>${esc(v)}</b><span>${esc(k)}</span></div>`).join("")}</div>

<div class="card"><h2>Hours played per day</h2>${daily(s.daily, now)}
<details><summary class="muted">As a table</summary><table><tr><th>Day</th><th>Hours</th></tr>
${s.daily.slice().reverse().map((d) => `<tr><td>${d.day}</td><td class="n">${h1(d.hours)}</td></tr>`).join("")}</table></details></div>

<div class="grid2">
<div class="card"><h2>Hours by platform</h2>${bars(s.platforms.map((p) => ({ label: p.platform, value: p.hours })))}</div>
<div class="card"><h2>Hours by time of day (UTC)</h2>${bars(s.hour_of_day.map((h) => ({ label: `${String(h.hour).padStart(2, "0")}:00`, value: h.hours })))}</div>
<div class="card"><h2>Builds, newest first</h2>${bars(s.versions.slice(0, 20).map((v) => ({ label: v.version, value: v.launches, note: v.hours ? `${h1(v.hours)} h` : "" })), (n) => `${n.toLocaleString("en-GB")} launches`)}</div>
<div class="card"><h2>Session length</h2>${t.runs ? bars(s.session_lengths.map((b) => ({ label: b.label, value: b.runs })), (n) => `${n} runs`) : `<p class="muted">Nothing yet.</p>`}</div>
<div class="card"><h2>Countries</h2>${bars(s.countries.map((c) => ({ label: c.country, value: c.hours, note: `${c.runs} runs` })))}</div>
</div>

<details class="card"><summary><b>Launches in the last 7 days</b></summary><table><tr><th>Started (UTC)</th><th>Platform</th><th>Build</th><th>Country</th><th>Played</th></tr>
${s.recent_runs.map((r) => `<tr><td>${esc(r.started_at.slice(0, 16).replace("T", " "))}</td><td>${esc(r.platform)}</td><td>${esc(r.version)}</td><td>${esc(r.country || "–")}</td><td class="n">${mins(r.secs)}</td></tr>`).join("")}</table></details>
</main></body></html>`;
}
