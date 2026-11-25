# Online play server

The server behind online rooms, rounds played in your own time and the daily
leaderboard ([docs/online-play.md](../docs/online-play.md)). It runs as a
Cloudflare Worker (`lidarlinks`) with Durable Objects on the free plan, at
`https://lidarlinks.openmcm2-laps.workers.dev` (`OnlineSettings.DEFAULT_SERVER`).
It is plain JavaScript with no dependencies, and `node --test "test/*.test.js"`
tests it without Cloudflare (`npx wrangler@4 dev` runs the real thing
locally).

The game asks `GET /` once at the start and shows Play online and
Leaderboard only when the server answers, so the game is fine while it isn't
deployed, or offline.

## What it does

- **Live rooms.** `POST /rooms` makes a room and returns a 4-letter code. Each
  player's game opens a WebSocket to `/rooms/CODE`. The first player in is
  the host and starts the round. From then on every game plays the whole
  round in step, from the host's setup (with its seed) and one numbered
  stream of events: each shot's inputs and each drop. Each game replays the
  others' shots through its own physics and reports any shot that stops
  somewhere else. The server relays messages and checks who may send what
  (`src/room.js`), but it never runs any golf.
- **Rounds in your own time.** `POST /games` starts one: the server picks the
  seed, so nobody can reroll the wind. Each player sends their `RoundRecord`
  as they play (`/games/ID/record`). Shots already sent can't be changed or
  taken back (`src/game.js`). `GET /games/ID` shows everyone's progress.
- **Players** have no accounts. Each game makes a random token and keeps it
  in `user://`. The server stores only a hash of it, and names are checked
  for length and characters.

### Low bandwidth, low latency

- A shot is sent as its inputs (club, aim, power, accuracy or the mouse
  stroke, where it stopped), about half a KB of JSON. Every game plays it
  through its own physics, so no ball positions stream during the flight. A
  whole four-player round is a couple of hundred KB, far less than one
  photo, so it plays fine on 2G or a weak phone signal.
- Your own shot plays at once: the meter never waits on the network. The
  others' shots arrive one hop through Cloudflare's edge (tens of ms).
- Keep-alives are a 15-byte ping every 15 s, answered by Cloudflare without
  waking the room (WebSocket auto-response), so they cost nothing.
- **Dropped connections heal.** If a game's connection drops in a round, its
  player keeps their seat for three minutes (`AWAY_GRACE_MS`). The game
  reconnects by itself with the key from its `welcome`, gets every event it
  missed, and resends any of its own the server never got. Only after the
  grace does the host's game take over their players.

### Daily leaderboard

`/boards/daily-DATE` (UTC date). Finishing the daily round sends its result
code (gzipped `RoundRecord`, a few KB). The server decodes it and checks it is
that day's seed (`dailySeed`, the same as `DailyRound.seed_for`), stroke
play, one human player, finished, and that the shots add up to the card. It
keeps each player's best and ranks by strokes (the same order as to par,
since everyone plays the same course). Rounds can be sent for the day and up
to six hours after it. Each entry's round can be fetched
(`/boards/daily-DATE/rounds/ROUND`) so anyone's game can re-run it.

### Room messages

Every message is JSON with a `type`. A new connection's first message is
`{type: "hello", v: 1, name}`, and the server answers with `welcome {code,
you, seat, host, key, seq}`. A game coming back after a dropped connection
sends `{type: "hello", v: 1, name, rejoin: {id, key}, since}` instead. Everyone also gets `members` whenever someone comes or
goes. Nobody can join once the round has started.

| From | Type | Goes to | Notes |
|---|---|---|---|
| host | `setup {owners, seed, ...}` | everyone else | Starts the round. `owners[i]` is the room seat whose game plays player `i` (computer golfers are the host's) |
| owner of `player` | `event {seq, player, kind: "shot" or "drop", ...}` | everyone else | Must be the next `seq` |
| host | `state`, `end` | everyone else | `end` closes the room |
| anyone | `chat {id}` | everyone | Quick-chat number, 0 to 7; no free text |
| anyone | `mismatch {shot}` | everyone | My replay of that event disagrees |
| anyone | `ping` | sender (`pong`) | Answered without waking the room |
| server | `away`, `back` | everyone else | A player's connection dropped, or they reconnected |
| server | `members`, `left`, `host_left`, `owners`, `error {reason}` | | When someone leaves, the host's game plays their players (`owners`). When the host leaves, the oldest remaining player becomes host |

Limits: four players, 64 KB a message, 256 KB a round record. Idle rooms are
deleted after 6 hours, and rounds 30 days after their last shot.

### Known gaps

- The server doesn't re-run shots yet (phase 3), so rounds in your own time
  trust each game's physics. A friend's game can still check a result code.
- The seed is known from the start, so someone could rehearse a round offline
  before sending it. Ranked challenges will need the seed revealed hole by
  hole.

## Deploying

It runs on Michael's Cloudflare account (free plan, account subdomain
`openmcm2-laps`). Either:

- **Workers Builds (no tokens):** in the Cloudflare dashboard, Workers &
  Pages > Create > Import a repository, pick this repo, set the root
  directory to `server`, Deploy. Cloudflare then redeploys by itself on every
  merge to `main`.
- **GitHub Actions:** add `CLOUDFLARE_API_TOKEN` (from the "Edit Cloudflare
  Workers" token template) and `CLOUDFLARE_ACCOUNT_ID` as repo secrets; the
  "Deploy online server" workflow then deploys on merges that touch
  `server/` (and can be run by hand).

The free plan's daily request limits are far beyond what a few rounds use. A
golf round sends a few messages per shot.
