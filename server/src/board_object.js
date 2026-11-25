// The Durable Object behind one leaderboard (board.js).
//
//   GET  /boards/KEY?token=T           -> view (with your place if T given)
//   POST /boards/KEY {token, name, par, code} -> {improved, rank, ...view}
//   GET  /boards/KEY/rounds/ROUND       -> {code}  that round, to watch or check
//   POST /boards/KEY/hide/ROUND  (ADMIN_PASSWORD) -> view  takes that entry off for good
//
// `code` is the game's result code (RoundRecord.to_code: "OLR1-" and the
// gzipped record in URL-safe base64), so a whole round is a few KB.

import { BoardState, boardOpen, checkRecord } from "./board.js";
import { MAX_RECORD_BYTES, hashToken, isAdmin, isToken } from "./protocol.js";

// Boards are kept for a year.
const KEEP_MS = 366 * 24 * 60 * 60 * 1000;

export async function decodeCode(code) {
  if (typeof code !== "string" || !code.startsWith("OLR1-") || code.length > MAX_RECORD_BYTES) return null;
  try {
    let b64 = code.slice(5).replace(/-/g, "+").replace(/_/g, "/");
    while (b64.length % 4) b64 += "=";
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
    const text = await new Response(stream).text();
    if (text.length > 4 * 1024 * 1024) return null;
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export class BoardObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.board = null;
    ctx.blockConcurrencyWhile(async () => {
      const data = await ctx.storage.get("board");
      if (data) this.board = new BoardState(data.key, data);
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    const key = url.searchParams.get("key");
    if (!this.board) this.board = new BoardState(key);
    const parts = url.pathname.split("/").filter(Boolean);
    if (request.method === "GET" && parts[0] === "rounds" && parts[1]) {
      const id = this.board.find(parts[1]);
      const code = id ? await this.ctx.storage.get("rec:" + id) : null;
      if (!code) return Response.json({ error: "no such round" }, { status: 404 });
      return Response.json({ code });
    }
    if (request.method === "GET") {
      const token = url.searchParams.get("token");
      const id = isToken(token) ? await hashToken(token) : null;
      return Response.json(this.board.view(id));
    }
    if (request.method !== "POST") return Response.json({ error: "not found" }, { status: 404 });
    if (parts[0] === "hide" && parts[1]) {
      // POST /boards/KEY/hide/ROUND with the ADMIN_PASSWORD (basic auth): takes a faked or rude entry off for good
      if (!isAdmin(request, this.env)) return Response.json({ error: "password needed" }, { status: 401 });
      const id = this.board.hide(parts[1]);
      if (!id) return Response.json({ error: "no such round" }, { status: 404 });
      await this.ctx.storage.delete("rec:" + id);
      await this.ctx.storage.put("board", this.board.toJSON());
      return Response.json(this.board.view());
    }
    if (parts.length) return Response.json({ error: "not found" }, { status: 404 });
    const text = await request.text();
    if (text.length > MAX_RECORD_BYTES) return Response.json({ error: "too large" }, { status: 413 });
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return Response.json({ error: "not JSON" }, { status: 400 });
    }
    const now = Date.now();
    if (!boardOpen(this.board.key, now)) return Response.json({ error: "that day's board has closed" }, { status: 403 });
    if (!isToken(body.token)) return Response.json({ error: "bad token" }, { status: 400 });
    const record = await decodeCode(body.code);
    const checked = checkRecord(this.board.key, record);
    if (checked.error) return Response.json({ error: checked.error }, { status: 400 });
    const id = await hashToken(body.token);
    const out = this.board.submit(id, body.name, checked.strokes, checked.holes, now, body.par);
    if (out.error) return Response.json({ error: out.error }, { status: 400 });
    if (out.improved) await this.ctx.storage.put("rec:" + id, body.code);
    await this.ctx.storage.put("board", this.board.toJSON());
    await this.ctx.storage.setAlarm(now + KEEP_MS);
    return Response.json({ ...this.board.view(id), improved: out.improved, rank: out.rank });
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
    this.board = null;
  }
}
