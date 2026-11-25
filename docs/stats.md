# Stats and the play-time count

## Your stats (kept on the device)

`PlayerStats` (`game/scripts/player_stats.gd`) keeps everything played on this device in `user://stats.cfg` (the browser
keeps it in the page's own storage): time played, sessions, days played, rounds started and finished, holes, shots,
scoring against par, fairways, greens in regulation, putts, longest and average drive, longest putt holed, longest
hole-out, scores by type (holes in one to doubles), the ball's total distance, the favourite club, water and out of
bounds, courses played, best round per course and length, and practice balls. Only the person's own shots count: never a
computer golfer's, nor another player's online. Each player's rounds, handicap index and records stay in
`PlayerProfiles` (the Players page).

The main menu's **Stats** page (`StatsPanel`) shows it all, with the last 30 days of play as bars and each player's
handicap index round by round. **Reset stats** starts the device's stats again (players' rounds stay).

The desktop launcher's **Stats** tab shows the same. The game writes a `[summary]` section into `stats.cfg`, already
worded in the person's units, when it starts, when a round ends and when it quits (`PlayerStats.write_summary`); the
launcher (`launcher/scripts/game_stats.gd`) only reads it.

### The play-time clock

There is one clock, used by the stats, the anonymous count and Support's once-ever thank-you line: it runs while a round
or the range is on screen, the game window has focus, nothing is paused, and someone has touched a key, the mouse, the
screen or a pad in the last 5 minutes (`PlayerStats.IDLE_S`). Play time from `support.cfg` (before the stats) is
carried over once.

## The anonymous play-time count

Built the same way as OpenSGolf's, and exact to the second: so the project can see how many hours are played on each
system and build and for how long at a time, `PlayCount` (`game/scripts/play_count.gd`) reports to LidarLinks' own
counter (`stats/`, a Cloudflare Worker with a D1 database on the project's account):

- once when the game starts: `start/<platform>/<build>`, e.g. `start/windows/f191d18`;
- the run's play so far: `play/<platform>` with `t`, the whole seconds played in this run, every 5 minutes of play and
  whenever play stops (pause menu, the game in the background, someone away for 5 minutes, a round ending, the game
  closing).

`t` only grows, so the counter keeps each run's highest and adds only the increase: a lost or repeated report costs
nothing. The last total of each run is kept on the device and sent again at the next start, so a game closed, killed or
offline is still counted to the second.

`<platform>` is `windows`, `macos`, `linux`, `web`, `android`, `ios` or `other`, with `-arm64` on 64-bit ARM desktops.
Each report also carries the build, its number in the run and a run id: a random number made at each start, kept only
until that run's last total has gone, so one run's reports can be told apart but never tied to a person or to another
run. Nothing else is sent: no names, scores, rounds or courses, and no cookies. The counter keeps the country Cloudflare
reads from the address, never the address itself.

It is **on by default**. The first round says so once; **Settings > Play-time count** in the game, or **Privacy >
Play-time count** in the launcher, turns it off (and forgets the kept totals). Nothing is sent from tests, a headless
run or a local ("dev") build.
