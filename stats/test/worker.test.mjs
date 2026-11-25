import test from "node:test";
import assert from "node:assert/strict";
import { memoryDb } from "./d1shim.mjs";
import worker, { SLACK_SECS, believable, cachedStats, readCount, storeCount, stats, underLimit } from "../src/index.js";
import { page } from "../src/page.js";

const u = (q) => new URL(`https://x.test/count?${q}`);

test("only the game's own counts are read", () => {
  assert.deepEqual(readCount(u("e=start/windows/f191d18&s=0123abcd&n=0"), "GB"),
    { kind: "start", platform: "windows", version: "f191d18", sid: "0123abcd", n: 0, t: 0, country: "GB" });
  assert.equal(readCount(u("e=play/linux&v=f191d18&s=0123abcd&n=1&t=300"), "XX").platform, "linux");
  assert.equal(readCount(u("e=play/linux&v=f191d18&s=0123abcd&n=1&t=300"), "XX").t, 300);
  for (const q of ["e=play/amiga&v=f191d18&s=0123abcd&t=1", "e=play/web&s=0123abcd&t=1", "e=start/web/dev&s=0123abcd",
    "e=play/web&v=f191d18&s=NOTHEX!!&t=1", "e=play/web&v=f191d18&t=1", "e=other&v=f191d18&s=0123abcd",
    "e=play/web&v=f191d18&s=0123abcd&n=-1&t=60", "e=play/web&v=f191d18&s=0123abcd&n=1", "e=play/web&v=f191d18&s=kept&t=60",
    "e=play/web&v=f191d18&s=0123abcd&n=1&t=604801", "e=play-15min/web&v=f191d18&s=0123abcd&n=1"]) {
    assert.equal(readCount(u(q), "GB"), null, q);
  }
  assert.equal(readCount(u("e=start/web/f191d18&s=0123abcd"), "not a country").country, "");
});

test("a run's seconds add up once: repeats, late and lost reports", async () => {
  const db = memoryDb();
  const t = new Date("2026-11-20T10:05:00Z");
  const c = (q) => readCount(u(q), "GB");
  await storeCount(db, c("e=start/macos-arm64/f191d18&s=aaaaaaaa"), t);
  await storeCount(db, c("e=play/macos-arm64&v=f191d18&s=aaaaaaaa&n=1&t=300"), t);
  await storeCount(db, c("e=play/macos-arm64&v=f191d18&s=aaaaaaaa&n=1&t=300"), t); // a repeat
  // report 2 was lost; report 3 still brings the whole run
  await storeCount(db, c("e=play/macos-arm64&v=f191d18&s=aaaaaaaa&n=3&t=1800"), new Date("2026-11-20T11:01:00Z"));
  await storeCount(db, c("e=play/macos-arm64&v=f191d18&s=aaaaaaaa&n=2&t=600"), new Date("2026-11-20T11:02:00Z")); // late
  await storeCount(db, c("e=play/web&v=f191d18&s=bbbbbbbb&n=1&t=1000"), t); // no start seen: the run is made
  // the next start re-sends the last report of a run that was closed: only the increase counts
  await storeCount(db, c("e=play/web&v=f191d18&s=bbbbbbbb&n=2&t=1800"), new Date("2026-11-21T09:00:00Z"));
  await storeCount(db, c("e=play/web&v=f191d18&s=bbbbbbbb&n=2&t=1800"), new Date("2026-11-21T09:00:00Z"));
  const runs = db.raw.prepare("SELECT sid, beats, secs FROM runs ORDER BY sid").all();
  assert.deepEqual(runs.map((r) => [r.sid, r.beats, r.secs]), [["aaaaaaaa", 3, 1800], ["bbbbbbbb", 2, 1800]]);
  const hours = db.raw.prepare("SELECT hour, SUM(secs) AS s FROM play_hourly GROUP BY hour ORDER BY hour").all();
  assert.deepEqual(hours.map((h) => [h.hour, h.s]), [["2026-11-20T10", 1300], ["2026-11-20T11", 1500], ["2026-11-21T09", 800]]);
  const s = await stats(db, new Date("2026-11-22T00:00:00Z"));
  assert.equal(s.totals.hours, 1);
  assert.equal(s.totals.runs, 2);
  assert.equal(s.totals.median_session_secs, 1800);
  assert.ok(page(s).includes("LidarLinks play time"));
});

test("the Worker: counts and the page are open", async () => {
  const env = { DB: memoryDb() };
  const res = await worker.fetch(new Request("https://x.test/count?e=start/web/f191d18&s=0123abcd"), env);
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
  assert.equal((await worker.fetch(new Request("https://x.test/count?e=junk"), env)).status, 204);
  assert.equal(env.DB.raw.prepare("SELECT COUNT(*) AS n FROM runs").get().n, 1);
  assert.equal((await worker.fetch(new Request("https://x.test/"), env)).status, 200);
  const ok = await worker.fetch(new Request("https://x.test/api/stats"), env);
  assert.equal(ok.status, 200);
  assert.equal((await ok.json()).totals.runs, 1);
});

test("made-up reports can't add more play than time has passed", async () => {
  const now = new Date("2026-11-20T12:00:00Z");
  assert.equal(believable(600, "2026-11-20T11:50:00Z", now), 600);
  assert.equal(believable(7 * 24 * 3600, "2026-11-20T12:00:00Z", now), SLACK_SECS, "a brand-new run claiming a week");
  assert.equal(believable(5000, "2026-11-20T11:00:00Z", now), 5000);
  assert.equal(believable(9000, "2026-11-20T11:00:00Z", now), 3600 + SLACK_SECS);
  const db = memoryDb();
  for (let i = 0; i < 3; i++) {
    await storeCount(db, readCount(u(`e=play/web&v=f191d18&s=f00d000${i}&n=1&t=604800`), "GB"), now);
  }
  const s = await stats(db, now);
  assert.equal(Math.round(s.totals.hours * 3600), 3 * SLACK_SECS);
});

test("the open page is worked out at most once a minute, and floods get a 429", async () => {
  const db = memoryDb();
  const t = new Date("2026-11-20T12:00:00Z");
  const a = await cachedStats(db, t);
  assert.equal(await cachedStats(db, new Date(t.getTime() + 30e3)), a);
  assert.notEqual(await cachedStats(db, new Date(t.getTime() + 61e3)), a);
  const req = new Request("https://x.test/", { headers: { "CF-Connecting-IP": "9.9.9.9" } });
  let n = 0;
  const env = { DB: db, LIMITER: { limit: async ({ key }) => ({ success: key === "page:9.9.9.9" && ++n <= 1 }) } };
  assert.ok(await underLimit(env, req, "page"));
  assert.ok(!(await underLimit(env, req, "page")));
  assert.equal((await worker.fetch(req, env)).status, 429);
  assert.ok(await underLimit({}, req, "page"), "no binding: allowed");
});
