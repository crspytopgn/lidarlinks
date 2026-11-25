// The Durable Object behind one live room. Uses the WebSocket Hibernation
// API, so an idle room costs nothing while players think about their shot,
// and keep-alive pings are answered without waking it at all.

import { RoomState } from "./room.js";
import { MAX_MESSAGE_BYTES } from "./protocol.js";

// Rooms nobody has used for this long are deleted.
const IDLE_MS = 6 * 60 * 60 * 1000;
// The keep-alive games send every few seconds (WebSocketLink.PING) and its
// answer, both as short as they can be.
export const PING = '{"type":"ping"}';
export const PONG = '{"type":"pong"}';

export class RoomObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.room = null;
    if (typeof WebSocketRequestResponsePair !== "undefined" && ctx.setWebSocketAutoResponse) {
      ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(PING, PONG));
    }
    ctx.blockConcurrencyWhile(async () => {
      const data = await ctx.storage.get("room");
      if (data) {
        this.room = new RoomState(data.code, data);
        const events = await ctx.storage.list({ prefix: "ev:" });
        this.room.events = [...events.values()].sort((a, b) => a.seq - b.seq);
      }
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/create") {
      if (this.room) return new Response("taken", { status: 409 });
      this.room = new RoomState(url.searchParams.get("code"));
      await this._save();
      return Response.json({ code: this.room.code });
    }
    if (!this.room) return new Response("no such room", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected a websocket", { status: 426 });
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ id: 0 });
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws, data) {
    if (typeof data !== "string" || data.length > MAX_MESSAGE_BYTES) {
      ws.send(JSON.stringify({ type: "error", reason: "message too large" }));
      return;
    }
    if (data === PING) {
      ws.send(PONG);
      return;
    }
    let msg;
    try {
      msg = JSON.parse(data);
    } catch {
      ws.send(JSON.stringify({ type: "error", reason: "not JSON" }));
      return;
    }
    const { id } = ws.deserializeAttachment() || { id: 0 };
    if (id === 0) {
      const joined = this.room.join(msg);
      if (joined.error) {
        ws.send(JSON.stringify({ type: "error", reason: joined.error }));
        ws.close(4000, joined.error.slice(0, 100));
        return;
      }
      // A game coming back: close the old connection it left behind.
      for (const other of this.ctx.getWebSockets()) {
        if (other !== ws && (other.deserializeAttachment() || {}).id === joined.id) {
          other.serializeAttachment({ id: -1 });
          try {
            other.close(4001, "reconnected");
          } catch {
            // already gone
          }
        }
      }
      ws.serializeAttachment({ id: joined.id });
      await this._deliver(joined.sends);
      return;
    }
    if (id < 0) return;
    const out = this.room.message(id, msg);
    if (out.error) {
      ws.send(JSON.stringify({ type: "error", reason: out.error }));
      return;
    }
    if (out.event) await this.ctx.storage.put("ev:" + String(out.event.seq).padStart(6, "0"), out.event);
    await this._deliver(out.sends);
  }

  async webSocketClose(ws) {
    await this._gone(ws);
  }

  async webSocketError(ws) {
    await this._gone(ws);
  }

  async alarm() {
    if (!this.room) return;
    const now = Date.now();
    const expired = this.room.expire(now);
    if (expired.length) {
      await this._deliver(expired);
      return;
    }
    if (this.ctx.getWebSockets().length === 0 && this.room.nextExpiry() === null) {
      await this.ctx.storage.deleteAll();
      this.room = null;
    } else {
      await this._setAlarm();
    }
  }

  async _gone(ws) {
    const { id } = ws.deserializeAttachment() || { id: 0 };
    if (id > 0 && this.room) await this._deliver(this.room.away(id, Date.now()));
  }

  async _deliver(sends) {
    const sockets = this.ctx.getWebSockets();
    const idOf = (ws) => (ws.deserializeAttachment() || { id: 0 }).id;
    for (const { to, msg } of sends) {
      const text = JSON.stringify(msg);
      for (const ws of sockets) {
        const id = idOf(ws);
        if (id <= 0) continue;
        const hit = to === "all" || to === id || (typeof to === "object" && to.except !== id);
        if (hit) {
          try {
            ws.send(text);
          } catch {
            // closed; webSocketClose tidies up
          }
        }
      }
    }
    await this._save();
  }

  async _save() {
    await this.ctx.storage.put("room", this.room.toJSON());
    await this._setAlarm();
  }

  // Wakes for the next player whose grace runs out, else after IDLE_MS.
  async _setAlarm() {
    const next = this.room ? this.room.nextExpiry() : null;
    await this.ctx.storage.setAlarm(next !== null ? next + 50 : Date.now() + IDLE_MS);
  }
}
