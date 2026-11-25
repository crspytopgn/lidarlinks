import test from "node:test";
import assert from "node:assert/strict";
import { gzipSync } from "node:zlib";
import { BoardState, boardOpen, checkRecord, isBoardKey } from "../src/board.js";
import { decodeCode } from "../src/board_object.js";
import { dailySeed, godotStringHash } from "../src/protocol.js";

const KEY = "daily-2026-11-25";
const card = [4, 3, 5, 4, 4, 3, 5, 4, 4];
const shots = (n) => Array.from({ length: n }, (_, i) => ({ index: i, power: 0.8 }));
const record = (extra = {}) => ({
  version: 1, seed: dailySeed("2026-11-25"), mode: 0, names: ["Ann"], computer: [-1],
  finished: true, cards: [card], shots: shots(36), ...extra,
});
const toCode = (r) => "OLR1-" + gzipSync(Buffer.from(JSON.stringify(r))).toString("base64url");

test("the daily seed matches the game's (DailyRound.seed_for, checked in run_tests.gd)", () => {
  assert.equal(godotStringHash(""), 5381);
  assert.equal(godotStringHash("a"), 177670);
  assert.equal(dailySeed("2026-11-25"), 615564749);
  assert.equal(dailySeed("2026-11-19"), 615564719);
});

test("board keys and when a day's board takes rounds", () => {
  assert.ok(isBoardKey(KEY));
  assert.ok(!isBoardKey("daily-2026-13-45") && !isBoardKey("weekly-2026-11-25") && !isBoardKey("daily-x"));
  const noon = Date.parse("2026-11-25T12:00:00Z");
  assert.ok(boardOpen(KEY, noon));
  assert.ok(boardOpen(KEY, Date.parse("2026-11-26T03:00:00Z")), "a round finished just after midnight");
  assert.ok(!boardOpen(KEY, Date.parse("2026-11-26T09:00:00Z")));
  assert.ok(!boardOpen(KEY, Date.parse("2026-11-24T12:00:00Z")));
});

test("only a finished daily round, played alone, goes on the board", () => {
  assert.deepEqual(checkRecord(KEY, record()), { strokes: 36, holes: 9 });
  assert.match(checkRecord(KEY, record({ seed: 5 })).error, /this day/);
  assert.match(checkRecord(KEY, record({ mode: 1 })).error, /stroke play/);
  assert.match(checkRecord(KEY, record({ names: ["A", "B"] })).error, /one player/);
  assert.match(checkRecord(KEY, record({ computer: [2] })).error, /computer/);
  assert.match(checkRecord(KEY, record({ finished: false })).error, /finished/);
  assert.match(checkRecord(KEY, record({ cards: [[1, 1, 1]] })).error, /card/);
  assert.match(checkRecord(KEY, record({ cards: [[0, 3, 5, 4, 4, 3, 5, 4, 4]] })).error, /score/);
  assert.match(checkRecord(KEY, record({ shots: shots(37) })).error, /add up/);
  assert.deepEqual(checkRecord(KEY, record({ shots: shots(34) })), { strokes: 36, holes: 9 }, "two penalty strokes");
  assert.match(checkRecord(KEY, null).error, /isn't a round/);
});

test("result codes decode on the server", async () => {
  const r = record();
  assert.deepEqual(await decodeCode(toCode(r)), r);
  assert.equal(await decodeCode("OLR1-notgzip"), null);
  assert.equal(await decodeCode("hello"), null);
});

test("each player's best round, ranked by strokes, ties to whoever got there first", () => {
  const b = new BoardState(KEY);
  assert.deepEqual(b.submit("a".repeat(64), "Ann", 38, 9, 1, 36), { improved: true, rank: 1 });
  assert.deepEqual(b.submit("b".repeat(64), "Bo", 36, 9, 2), { improved: true, rank: 1 });
  assert.deepEqual(b.submit("c".repeat(64), "Cy", 38, 9, 3), { improved: true, rank: 2 });
  assert.deepEqual(b.submit("a".repeat(64), "Ann", 40, 9, 4), { improved: false, rank: 2 }, "a worse round keeps the best");
  assert.deepEqual(b.submit("a".repeat(64), "Ann", 35, 9, 5), { improved: true, rank: 1 });
  assert.match(b.submit("d".repeat(64), "<b>", 30, 9, 6).error, /name/);
  assert.match(b.submit("d".repeat(64), "Di", 60, 18, 6).error, /holes/);
  const v = b.view("c".repeat(64));
  assert.deepEqual(v.entries.map((e) => [e.rank, e.name, e.strokes]), [[1, "Ann", 35], [2, "Bo", 36], [3, "Cy", 38]]);
  assert.deepEqual(v.you, { rank: 3, strokes: 38 });
  assert.equal(v.count, 3);
  assert.equal(v.par, 36, "only Ann's game said the par, and it's kept");
  assert.equal(b.find(v.entries[1].round), "b".repeat(64));
  const copy = new BoardState(KEY, JSON.parse(JSON.stringify(b.toJSON())));
  assert.equal(copy.rank("a".repeat(64)), 1);
});
