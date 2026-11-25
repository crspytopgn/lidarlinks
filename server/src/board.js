// A leaderboard: the daily round's board for one UTC day (board key
// "daily-2026-11-25"). Everyone plays the same course, pins, wind and seed
// that day (DailyRound), so boards rank gross strokes: the same order as to
// par. Each player keeps their best round; ties go to whoever got there
// first.
//
// Plain data plus pure methods, like RoomState. The round records
// themselves are stored beside the board (BoardObject), so anyone's game
// can fetch one and re-run it (RoundReplay) to check it.

import { cleanName, dailySeed, utcDate } from "./protocol.js";

export const MAX_ENTRIES = 1000;
export const SHOWN = 50;
/** The most holes in one a believable card has. */
export const MAX_ACES = 2;
/** The fewest strokes a hole a believable card averages. */
export const MIN_PER_HOLE = 2.5;

export function isBoardKey(key) {
  return typeof key === "string" && /^daily-\d{4}-\d{2}-\d{2}$/.test(key) && !Number.isNaN(Date.parse(key.slice(6)));
}

// Can a round be sent to board `key` at time `now`? The day's own board, and
// for a few hours after midnight UTC yesterday's (a round started late).
export function boardOpen(key, now) {
  const date = key.slice(6);
  return date === utcDate(now) || date === utcDate(now - 6 * 60 * 60 * 1000);
}

// Checks a decoded RoundRecord (record.to_dict in the game) against board
// `key`. Returns {strokes, holes} or {error}.
export function checkRecord(key, record) {
  if (!record || typeof record !== "object") return { error: "that isn't a round" };
  if (record.version !== 1) return { error: "update the game" };
  const date = key.slice(6);
  if (record.seed !== dailySeed(date)) return { error: "that isn't this day's round" };
  if (record.mode !== 0) return { error: "daily rounds are stroke play" };
  if (!Array.isArray(record.names) || record.names.length !== 1) return { error: "daily rounds are for one player" };
  if (!Array.isArray(record.computer) || record.computer[0] !== -1) return { error: "computer golfers don't go on the board" };
  if (record.finished !== true) return { error: "the round isn't finished" };
  const card = Array.isArray(record.cards) ? record.cards[0] : null;
  if (!Array.isArray(card) || card.length < 9 || card.length > 18) return { error: "the card is missing" };
  let strokes = 0;
  let aces = 0;
  for (const v of card) {
    if (!Number.isInteger(v) || v < 1 || v > 20) return { error: "every hole needs a score" };
    strokes += v;
    if (v === 1) aces++;
  }
  // A made-up card is the easy way to cheat until the server can re-run rounds (docs/online-play.md, phase 3), so the
  // impossible ones are turned away: more than two holes in one, or under 2.5 a hole (27 under on 18 holes).
  if (aces > MAX_ACES || strokes < Math.ceil(card.length * MIN_PER_HOLE)) return { error: "that score can't be right" };
  const shots = Array.isArray(record.shots) ? record.shots.filter((s) => s && !s.mulligan) : [];
  // Each stroke on the card is a shot in the record, except penalty strokes.
  if (shots.length > strokes || shots.length < card.length) return { error: "the shots don't add up to the card" };
  return { strokes, holes: card.length };
}

export class BoardState {
  constructor(key, data = null) {
    this.key = key;
    // {id, name, strokes, holes, at}
    this.entries = [];
    // ids taken off the board by hand (BoardObject's /hide): they can't come back that day
    this.hidden = [];
    if (data) Object.assign(this, data);
  }

  toJSON() {
    return { key: this.key, entries: this.entries, hidden: this.hidden };
  }

  _sort() {
    this.entries.sort((a, b) => a.strokes - b.strokes || a.at - b.at);
  }

  // Player `id` (a hash of their token) sent a round. Returns {improved,
  // rank} or {error}.
  submit(id, name, strokes, holes, now, par = 0) {
    const clean = cleanName(name);
    if (!clean) return { error: "pick a name of 1 to 20 letters" };
    if (this.hidden.includes(id)) return { error: "that round was taken off the board" };
    if (!Number.isInteger(par) || par < holes * 3 || par > holes * 5) par = 0;
    if (this.entries.length && this.entries[0].holes !== holes) return { error: "that round has a different number of holes" };
    const mine = this.entries.find((e) => e.id === id);
    let improved = false;
    if (!mine) {
      this.entries.push({ id, name: clean, strokes, holes, at: now, par });
      improved = true;
    } else {
      mine.name = clean;
      if (par) mine.par = par;
      if (strokes < mine.strokes) {
        mine.strokes = strokes;
        mine.at = now;
        improved = true;
      }
    }
    this._sort();
    if (this.entries.length > MAX_ENTRIES) this.entries.length = MAX_ENTRIES;
    const rank = this.rank(id);
    return { improved, rank };
  }

  // The course's par as most players' games give it (only for showing
  // scores to par; the order is by strokes), or 0.
  par() {
    const votes = new Map();
    for (const e of this.entries) if (e.par) votes.set(e.par, (votes.get(e.par) || 0) + 1);
    let best = 0;
    let n = 0;
    for (const [p, c] of votes) if (c > n) [best, n] = [p, c];
    return best;
  }

  // 1-based place of player `id`, counting ties as the same place, or 0.
  rank(id) {
    const i = this.entries.findIndex((e) => e.id === id);
    if (i < 0) return 0;
    const s = this.entries[i].strokes;
    return this.entries.findIndex((e) => e.strokes === s) + 1;
  }

  // What the game shows: the top SHOWN, the player's own place, and how many
  // played. Ids are cut short: enough to fetch a round, not to pose as them.
  view(id = null) {
    const out = [];
    let place = 0;
    for (let i = 0; i < Math.min(SHOWN, this.entries.length); i++) {
      const e = this.entries[i];
      if (i === 0 || e.strokes !== this.entries[i - 1].strokes) place = i + 1;
      out.push({ rank: place, name: e.name, strokes: e.strokes, round: e.id.slice(0, 16) });
    }
    const v = { key: this.key, count: this.entries.length, holes: this.entries.length ? this.entries[0].holes : 0, par: this.par(), entries: out };
    if (id) {
      const mine = this.entries.find((e) => e.id === id);
      if (mine) v.you = { rank: this.rank(id), strokes: mine.strokes };
    }
    return v;
  }

  // Takes the entry with short round id `shortId` off the board for good. Returns its full id, or null.
  hide(shortId) {
    const id = this.find(shortId);
    if (!id) return null;
    this.entries = this.entries.filter((e) => e.id !== id);
    if (!this.hidden.includes(id)) this.hidden.push(id);
    return id;
  }

  // The full id of a short round id from view(), or null.
  find(shortId) {
    const e = this.entries.find((x) => x.id.slice(0, 16) === shortId);
    return e ? e.id : null;
  }
}
