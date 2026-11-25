// LidarLinks' anonymous play-time count (stats/README.md): a Cloudflare Worker with a D1 database, built the same way
// as OpenSGolf's play-time counter, but counting seconds rather than 15-minute marks.
//
// * GET /count?e=<event>&v=<version>&s=<run id>&n=<report>&t=<seconds>: what the game sends (game/scripts/play_count.gd).
//   `e` is start/<platform>/<version> once at start or play/<platform> with `t` the whole seconds played in this run so
//   far (every 5 minutes of play, and when the game is paused, put in the background or closed); `s` a random id the game
//   makes at each start (kept only until the next start re-sends the last report); `n` the report's number in the run.
//   `t` adds up, so a lost or repeated report costs nothing: the highest `t` per run is kept and only its increase is
//   added to the hour it arrived in. Nothing else is kept: no address, only the country Cloudflare reads from it.
// * GET /: the stats page, open to anyone; GET /api/stats the same as JSON.

/** Platforms the game names (PlayCount.platform). */
export const PLATFORMS = new Set([
  "windows", "macos", "linux", "web", "android", "ios", "other",
  "windows-arm64", "macos-arm64", "linux-arm64", "other-arm64",
]);

/** An event's parts, or null when it is not one of the game's. */
export function parseEvent(e) {
  if (typeof e !== "string" || e.length > 64) return null;
  const p = e.split("/");
  if (p[0] === "start" && p.length === 3 && PLATFORMS.has(p[1]) && isVersion(p[2])) {
    return { kind: "start", platform: p[1], version: p[2] };
  }
  if (p[0] === "play" && p.length === 2 && PLATFORMS.has(p[1])) return { kind: "play", platform: p[1] };
  return null;
}

/** The game's version: the short commit it was built from (BuildInfo.COMMIT). */
export function isVersion(v) {
  return typeof v === "string" && /^[0-9a-f]{7,12}$/.test(v);
}

/** The most play one run may report: a week. */
export const MAX_SECS = 7 * 24 * 3600;

/** A run id: 8 to 32 hex digits. */
export function isRunId(s) {
  return typeof s === "string" && /^[0-9a-f]{8,32}$/.test(s);
}

/** 'YYYY-MM-DDTHH' of a Date, in UTC. */
export function hourOf(d) {
  return d.toISOString().slice(0, 13);
}

/** A count's request, checked: what to store, or null to ignore it. */
export function readCount(url, country) {
  const q = url.searchParams;
  const ev = parseEvent(q.get("e"));
  if (!ev) return null;
  const version = ev.kind === "start" ? ev.version : q.get("v");
  if (!isVersion(version)) return null;
  const s = q.get("s") || "";
  if (!isRunId(s)) return null;
  const n = Number.parseInt(q.get("n") || "0", 10);
  if (!Number.isFinite(n) || n < 0 || n > 100000) return null;
  let t = 0;
  if (ev.kind === "play") {
    t = Number.parseInt(q.get("t") || "", 10);
    if (!Number.isFinite(t) || t < 0 || t > MAX_SECS) return null;
  }
  const c = typeof country === "string" && /^[A-Z0-9]{2}$/.test(country) ? country : "";
  return { kind: ev.kind, platform: ev.platform, version, sid: s, n, t, country: c };
}

/** Stores one count. A run's play only ever grows: a report at or below the run's highest `t` (a repeat, or one that
 * arrived late) changes nothing. */
export async function storeCount(db, c, now) {
  const at = now.toISOString();
  await db.prepare(
    `INSERT INTO runs (sid, platform, version, country, started_at, last_at, beats, secs) VALUES (?1, ?2, ?3, ?4, ?5, ?5, 0, 0)
     ON CONFLICT (sid) DO NOTHING`,
  ).bind(c.sid, c.platform, c.version, c.country, at).run();
  if (c.kind !== "play") return;
  const run = await db.prepare(`SELECT secs, platform, version, country FROM runs WHERE sid = ?1`).bind(c.sid).first();
  if (!run || c.t <= run.secs) return;
  const r = await db.prepare(`UPDATE runs SET secs = ?2, beats = MAX(beats, ?3), last_at = ?4 WHERE sid = ?1 AND secs = ?5`)
    .bind(c.sid, c.t, c.n, at, run.secs).run();
  if (!r.meta || r.meta.changes === 0) return;  // another report for the run got there first
  // the run's own platform, build and country: a report re-sent at the next start comes from the same build
  await db.prepare(
    `INSERT INTO play_hourly (hour, platform, version, country, kept, secs) VALUES (?1, ?2, ?3, ?4, 0, ?5)
     ON CONFLICT (hour, platform, version, country, kept) DO UPDATE SET secs = secs + ?5`,
  ).bind(hourOf(now), run.platform, run.version, run.country, c.t - run.secs).run();
}

/** Session-length buckets, by seconds played in the run: [label, from, up to (not included)]. */
export const LENGTHS = [
  ["under 5 min", 0, 300], ["5–15 min", 300, 900], ["15–30 min", 900, 1800], ["30 min–1 h", 1800, 3600],
  ["1–2 h", 3600, 7200], ["2–4 h", 7200, 14400], ["4 h or more", 14400, 1e12],
];

/** The stats for the page. */
export async function stats(db, now = new Date()) {
  const all = async (sql, ...p) => (await db.prepare(sql).bind(...p).all()).results || [];
  const day30 = new Date(now.getTime() - 30 * 86400e3).toISOString().slice(0, 10);
  const day7 = new Date(now.getTime() - 7 * 86400e3).toISOString().slice(0, 13);

  const daily = await all(`SELECT substr(hour, 1, 10) AS day, SUM(secs) AS secs FROM play_hourly GROUP BY day ORDER BY day`);
  const platforms = await all(`SELECT platform, SUM(secs) AS secs FROM play_hourly GROUP BY platform ORDER BY secs DESC`);
  const launches = await all(`SELECT version, COUNT(*) AS launches FROM runs GROUP BY version`);
  const versionHours = await all(`SELECT version, SUM(secs) AS secs FROM play_hourly GROUP BY version`);
  const hourOfDay = await all(`SELECT CAST(substr(hour, 12, 2) AS INTEGER) AS h, SUM(secs) AS secs FROM play_hourly GROUP BY h`);
  const runSecs = await all(`SELECT secs FROM runs ORDER BY secs`);
  const countries = await all(`
    SELECT country, COUNT(*) AS runs, SUM(secs) AS secs FROM runs GROUP BY country ORDER BY secs DESC, runs DESC LIMIT 25`);
  const recentRuns = await all(`
    SELECT platform, version, country, started_at, secs FROM runs WHERE started_at >= ?1 ORDER BY started_at DESC LIMIT 50`, day7);
  const firstSeen = await all(`SELECT version, MIN(started_at) AS first FROM runs GROUP BY version`);
  const runs7 = await db.prepare(`SELECT COUNT(*) AS n FROM runs WHERE started_at >= ?1`).bind(day7).first();

  const totalRuns = runSecs.length;
  const median = totalRuns ? runSecs[Math.floor(totalRuns / 2)].secs : null;
  const vh = new Map(versionHours.map((r) => [r.version, r.secs]));
  const first = new Map(firstSeen.map((r) => [r.version, r.first]));
  const versions = launches.map((r) => ({
    version: r.version, launches: r.launches, hours: (vh.get(r.version) || 0) / 3600, first: first.get(r.version) || "",
  })).sort((a, b) => (b.first < a.first ? -1 : b.first > a.first ? 1 : 0));
  const total = daily.reduce((a, d) => a + d.secs, 0);
  const sumSince = (day) => daily.filter((d) => d.day >= day).reduce((a, d) => a + d.secs, 0);

  return {
    generated_at: now.toISOString(),
    totals: {
      hours: total / 3600, hours_7d: sumSince(day7.slice(0, 10)) / 3600, hours_30d: sumSince(day30) / 3600,
      runs: totalRuns, runs_7d: runs7 ? runs7.n : 0, median_session_secs: median,
    },
    daily: daily.map((d) => ({ day: d.day, hours: d.secs / 3600 })),
    platforms: platforms.map((p) => ({ platform: p.platform, hours: p.secs / 3600 })),
    versions,
    hour_of_day: Array.from({ length: 24 }, (_, h) => ({ hour: h, hours: (hourOfDay.find((r) => r.h === h) || { secs: 0 }).secs / 3600 })),
    session_lengths: LENGTHS.map(([label, lo, hi]) => ({ label, runs: runSecs.filter((r) => r.secs >= lo && r.secs < hi).length })),
    countries: countries.map((c) => ({ country: c.country || "unknown", runs: c.runs, hours: c.secs / 3600 })),
    recent_runs: recentRuns,
  };
}

const CORS = { "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/count") {
      if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...CORS, "Access-Control-Allow-Methods": "GET" } });
      const c = readCount(url, request.cf && request.cf.country);
      if (c) await storeCount(env.DB, c, new Date());
      // the same answer whether it was kept or not: the game only looks at whether it got through
      return new Response(null, { status: 204, headers: CORS });
    }
    if (url.pathname === "/robots.txt") return new Response("User-agent: *\nDisallow: /\n");
    // The page and its numbers are open to anyone: totals only, nothing about a person.
    if (url.pathname === "/api/stats") return Response.json(await stats(env.DB), { headers: { ...CORS, "Cache-Control": "public, max-age=60" } });
    if (url.pathname === "/") {
      const { page } = await import("./page.js");
      return new Response(page(await stats(env.DB)), { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=60" } });
    }
    return new Response("Not found", { status: 404 });
  },
};
