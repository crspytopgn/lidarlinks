import test from "node:test";
import assert from "node:assert/strict";
import { AWAY_GRACE_MS, RoomState } from "../src/room.js";
import { PROTOCOL_VERSION, cleanName, isCode, randomCode } from "../src/protocol.js";

const hello = (name) => ({ type: "hello", v: PROTOCOL_VERSION, name });
const typesTo = (sends, to) => sends.filter((s) => s.to === to || s.to === "all").map((s) => s.msg.type);

test("codes and names", () => {
  const c = randomCode(4);
  assert.ok(isCode(c, 4), c);
  assert.ok(!isCode("ABCI", 4) && !isCode("abc", 3) && !isCode("ABC", 4));
  assert.equal(cleanName("  Ann   Lee "), "Ann Lee");
  assert.equal(cleanName("Zoë O'Brien"), "Zoë O'Brien");
  assert.equal(cleanName(""), null);
  assert.equal(cleanName("x".repeat(21)), null);
  assert.equal(cleanName("<script>"), null);
});

test("joining: the first player hosts, seats fill in order, four at most", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann"));
  assert.equal(a.id, 1);
  assert.equal(room.host, 1);
  assert.deepEqual(typesTo(a.sends, 1), ["welcome", "members"]);
  const b = room.join(hello("Bo"));
  assert.equal(room.member(b.id).seat, 1);
  assert.match(room.join(hello("bo")).error, /already here/);
  room.join(hello("Cy"));
  room.join(hello("Di"));
  assert.match(room.join(hello("Ed")).error, /full/);
  assert.match(room.join({ type: "hello", v: 99, name: "X" }).error, /version/);
  assert.match(room.join({ type: "shot" }).error, /hello/);
});

test("players who come before the start get the setup; after it, nobody joins", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const b = room.join(hello("Bo")).id;
  assert.match(room.message(a, { type: "setup", owners: [0, 5] }).error, /owners/);
  assert.match(room.message(b, { type: "setup", owners: [0, 1] }).error, /only the host/);
  const setup = room.message(a, { type: "setup", owners: [0, 1, 0] });
  assert.deepEqual(setup.sends[0].to, { except: a });
  assert.match(room.message(a, { type: "setup", owners: [0] }).error, /started/);
  assert.match(room.join(hello("Cy")).error, /started/);
});

test("events: the next number, from the game that plays that player", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const b = room.join(hello("Bo")).id;
  const ev = (seq, player) => ({ type: "event", seq, player, kind: "shot", shot: { power: 1 } });
  assert.match(room.message(a, ev(0, 0)).error, /hasn't started/);
  room.message(a, { type: "setup", owners: [0, 1, 0] });
  assert.match(room.message(b, ev(0, 0)).error, /isn't yours/);
  assert.match(room.message(a, ev(1, 0)).error, /expected event 0/);
  assert.match(room.message(a, { ...ev(0, 0), kind: "teleport" }).error, /shots or drops/);
  const sent = room.message(a, ev(0, 0));
  assert.deepEqual(sent.sends, [{ to: { except: a }, msg: { ...ev(0, 0), from: 0 } }]);
  assert.ok(room.message(b, ev(1, 1)).sends);
  assert.ok(room.message(a, ev(2, 2)).sends, "the host plays the computer golfer");
  assert.match(room.message(a, ev(2, 0)).error, /expected event 3/);
});

test("quick chat, mismatch reports and pings", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const chat = room.message(a, { type: "chat", id: 2 });
  assert.deepEqual(chat.sends[0].msg, { type: "chat", id: 2, from: 0, name: "Ann" });
  assert.match(room.message(a, { type: "chat", id: 99 }).error, /quick chat/);
  assert.match(room.message(a, { type: "chat", text: "free text" }).error, /quick chat/);
  assert.equal(room.message(a, { type: "mismatch", shot: 7 }).sends[0].msg.shot, 7);
  assert.deepEqual(room.message(a, { type: "ping" }).sends, [{ to: a, msg: { type: "pong" } }]);
  assert.match(room.message(a, { type: "nonsense" }).error, /unknown/);
  assert.match(room.message(42, { type: "ping" }).error, /not in the room/);
});

test("when someone leaves, the host plays their players; when the host leaves, the next player hosts", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const b = room.join(hello("Bo")).id;
  const c = room.join(hello("Cy")).id;
  room.message(a, { type: "setup", owners: [0, 1, 2] });
  let sends = room.leave(c);
  assert.deepEqual(sends.map((s) => s.msg.type), ["left", "owners", "members"]);
  assert.deepEqual(room.setup.owners, [0, 1, 0]);
  sends = room.leave(a);
  assert.equal(room.host, b);
  assert.deepEqual(sends.map((s) => s.msg.type), ["host_left", "owners", "members"]);
  assert.deepEqual(sends[1].msg, { type: "owners", owners: [1, 1, 1], host: 1 });
  assert.ok(room.message(b, { type: "event", seq: 0, player: 0, kind: "shot" }).sends);
  room.message(b, { type: "end" });
  assert.match(room.join(hello("Di")).error, /finished/);
});

test("the state survives being stored", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  room.message(a, { type: "setup", course: "Kauri", owners: [0] });
  const copy = new RoomState("ABCD", JSON.parse(JSON.stringify(room.toJSON())));
  assert.equal(copy.host, a);
  assert.equal(copy.setup.course, "Kauri");
  assert.match(copy.join(hello("Bo")).error, /started/);
  assert.equal(copy.seq, 0);
});

test("a dropped connection keeps its seat for a while and catches up when it's back", () => {
  const room = new RoomState("ABCD");
  const aj = room.join(hello("Ann"));
  const a = aj.id;
  const bj = room.join(hello("Bo"));
  const b = bj.id;
  const bKey = bj.sends[0].msg.key;
  assert.match(bKey, /^[A-Za-z0-9_-]{24}$/);
  assert.notEqual(bKey, aj.sends[0].msg.key);
  room.message(a, { type: "setup", owners: [0, 1] });
  room.message(a, { type: "event", seq: 0, player: 0, kind: "shot", shot: { p: 1 } });
  // Bo's phone loses signal: Ann hears, but Bo keeps their seat.
  const away = room.away(b, 1000);
  assert.deepEqual(away.map((s) => s.msg.type), ["away"]);
  assert.deepEqual(room.setup.owners, [0, 1]);
  assert.equal(room.nextExpiry(), 1000 + AWAY_GRACE_MS);
  room.message(a, { type: "event", seq: 1, player: 0, kind: "shot", shot: { p: 2 } });
  assert.deepEqual(room.expire(1000 + AWAY_GRACE_MS - 1), []);
  // A wrong key, or a new name after the start, gets nowhere.
  assert.match(room.join({ ...hello("Bo"), rejoin: { id: b, key: "nope" } }).error, /away too long/);
  // Back with the key: the events from `since` on, and the server's number.
  const back = room.join({ ...hello("Bo"), rejoin: { id: b, key: bKey }, since: 1 });
  assert.equal(back.id, b);
  const mine = back.sends.filter((s) => s.to === b).map((s) => s.msg);
  assert.equal(mine[0].type, "welcome");
  assert.equal(mine[0].seq, 2);
  assert.equal(mine[1].type, "setup");
  assert.deepEqual(mine.filter((m) => m.type === "event").map((m) => m.seq), [1]);
  assert.ok(back.sends.some((s) => s.msg.type === "back"));
  assert.equal(room.nextExpiry(), null);
  // Bo plays on as before.
  assert.ok(room.message(b, { type: "event", seq: 2, player: 1, kind: "shot" }).sends);
});

test("away for longer than the grace: the host plays their players", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  const b = room.join(hello("Bo")).id;
  room.message(a, { type: "setup", owners: [0, 1] });
  room.away(b, 0);
  const sends = room.expire(AWAY_GRACE_MS);
  assert.deepEqual(sends.map((s) => s.msg.type), ["left", "owners", "members"]);
  assert.deepEqual(room.setup.owners, [0, 0]);
  // Before the round, a dropped player just leaves.
  const lobby = new RoomState("WXYZ");
  lobby.join(hello("Ann"));
  const c = lobby.join(hello("Cy")).id;
  assert.deepEqual(lobby.away(c, 0).map((s) => s.msg.type), ["left", "members"]);
});

test("the event log isn't in the stored state (each event is stored apart)", () => {
  const room = new RoomState("ABCD");
  const a = room.join(hello("Ann")).id;
  room.message(a, { type: "setup", owners: [0] });
  const out = room.message(a, { type: "event", seq: 0, player: 0, kind: "shot" });
  assert.equal(out.event.seq, 0);
  assert.equal(room.events.length, 1);
  assert.equal(JSON.parse(JSON.stringify(room.toJSON())).events, undefined);
});
