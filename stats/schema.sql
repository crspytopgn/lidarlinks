-- LidarLinks' anonymous play-time count (stats/README.md). Safe to run again: everything is IF NOT EXISTS.

-- One row per launch of a game that reports here. `sid` is a random number the game makes at start and never saves, so
-- one launch can be told from another but never linked to a player. `beats` is the number of the run's latest play
-- report and `secs` the highest total of seconds played it reported (totals only grow, so repeats count once).
CREATE TABLE IF NOT EXISTS runs (
  sid        TEXT PRIMARY KEY,
  platform   TEXT NOT NULL,
  version    TEXT NOT NULL,
  country    TEXT NOT NULL DEFAULT '',
  started_at TEXT NOT NULL,          -- ISO time (UTC) of the run's first count
  last_at    TEXT NOT NULL,          -- ISO time (UTC) of its latest count
  beats      INTEGER NOT NULL DEFAULT 0,
  secs       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS runs_started ON runs (started_at);

-- Seconds of play per hour (UTC) the reports arrived in: each report adds what its run's total grew by. `kept` is
-- unused (always 0), there for seconds that belong to no run.
CREATE TABLE IF NOT EXISTS play_hourly (
  hour     TEXT NOT NULL,            -- 'YYYY-MM-DDTHH' (UTC)
  platform TEXT NOT NULL,
  version  TEXT NOT NULL,
  country  TEXT NOT NULL DEFAULT '',
  kept     INTEGER NOT NULL DEFAULT 0,
  secs     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (hour, platform, version, country, kept)
);
