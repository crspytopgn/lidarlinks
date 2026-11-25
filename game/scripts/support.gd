class_name Support
extends RefCounted
## Where people can chip in to keep LidarLinks going. The main menu's
## Support button opens it, and so does a quiet line under the final
## scorecard, shown only once ever: after the first round that ends with
## about five hours of play behind the player; the
## launcher (launcher/scripts/paths.gd SUPPORT_PAGE) and the README use the
## same page. Never a pop-up and never in the way of play.

## Ko-fi first: it takes a card or PayPal with no account. GitHub Sponsors
## is the other way, linked from the README and the release notes.
const URL := "https://ko-fi.com/crspytopgn"
const SPONSORS_URL := "https://github.com/sponsors/crspytopgn"
const BUTTON := "Support"
const TOOLTIP := "LidarLinks is free, with no ads. This opens its Ko-fi page in your browser, if you'd like to chip in."
const THANKS := "Enjoying LidarLinks? It's free and made in spare time. Support it"


## Where the game keeps the play time and whether the after-round line has
## been shown.
const SEEN_PATH := "user://support.cfg"
## Play before the after-round line may show: people who keep coming back.
const HOURS_BEFORE_THANKS := 5.0
## A hole left open longer than this (the player walked away) counts only
## this much.
const MAX_HOLE_SECONDS := 1800.0


## Adds time spent playing (the main game adds each hole as it ends).
static func add_play_time(seconds: float, path := SEEN_PATH) -> void:
	if seconds <= 0.0:
		return
	var cfg := ConfigFile.new()
	cfg.load(path)
	var played: float = cfg.get_value("support", "played_s", 0.0)
	cfg.set_value("support", "played_s", played + minf(seconds, MAX_HOLE_SECONDS))
	cfg.save(path)


## True once ever: the first time it is asked after a finished round once
## the player has played HOURS_BEFORE_THANKS in all. Never again after that.
static func thank_once(path := SEEN_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	if cfg.get_value("support", "thanked", false):
		return false
	if float(cfg.get_value("support", "played_s", 0.0)) < HOURS_BEFORE_THANKS * 3600.0:
		return false
	cfg.set_value("support", "thanked", true)
	cfg.save(path)
	return true


## Opens the page in the browser (a new tab in the web build).
static func open() -> void:
	OS.shell_open(URL)
