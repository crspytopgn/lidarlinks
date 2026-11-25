# Play-time count

A Cloudflare Worker with a D1 database that keeps LidarLinks' anonymous play-time count (`game/scripts/play_count.gd`,
docs/stats.md) and shows it on an open page (totals only). It is built the same way as OpenSGolf's play-time counter, exact to the second (the two share the design).

* `GET /count?e=<event>&v=<build>&s=<run id>&n=<report>&t=<seconds>`: what the game sends. `e` is
  `start/<platform>/<build>` once at start and `play/<platform>` with `t` the whole seconds played in that run so far,
  every 5 minutes of play and when the game is paused, put in the background or closed. `s` is a random id made at each
  start; `n` the report's number in the run. Totals only grow, so the Worker keeps each run's highest `t` and adds only
  the increase to the hour it arrived in: a lost or repeated report costs nothing, and the game sends each run's last
  total again at its next start, so play is counted to the second. Only the country Cloudflare reads from the address
  is kept, never the address. Every answer is the same empty 204.
* `GET /` and `GET /api/stats`: the stats, open to anyone (totals only, nothing about a person). They are worked out
  at most once a minute per Worker instance (`cachedStats`), since every fresh answer reads the whole table.

### Abuse limits

* A run can't add more play than the time since its last count plus 30 minutes (`believable`), so a made-up report
  claiming a week adds 30 minutes, not a week. The price: a run whose earlier counts never got through (offline the
  whole time) only adds its last 30 minutes when it is re-sent at the next start.
* Counts and page views count towards 60 a minute per address (`underLimit`, the rate limiting binding `LIMITER` in
  `wrangler.toml`; the address is only the counter's key and is never stored). That stops one machine using up the
  account's daily D1 allowance, which OpenSGolf's boards share. On the free plan going over never costs money: D1
  just refuses queries until midnight UTC.

The game sends to `https://lidarlinks-stats.openmcm2-laps.workers.dev/count` (`PlayCount.URL`).

## Deploy

The D1 database `lidarlinks-stats` already exists (its id is in `wrangler.toml`) and has the tables in `schema.sql`.

```sh
cd stats
npx wrangler@4.152.0 deploy
```

Or in the Cloudflare dashboard: Workers & Pages > Create > Import a repository, pick this repository, name it
`lidarlinks-stats` and set the root directory to `stats`.

Until it is deployed the game's reports don't get through; each run's last total is kept on the device (up to 20 runs)
and sent again at the next start.

## Tests

`node --test stats/test/*.test.mjs` (Node 22.5 or later: the tests stand D1 in with node:sqlite).
