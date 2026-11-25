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


## Where the game keeps whether the after-round line has been shown. The
## play time itself is PlayerStats' clock, the game's only one.
const SEEN_PATH := "user://support.cfg"
## Play before the after-round line may show: people who keep coming back.
const HOURS_BEFORE_THANKS := 5.0


## True once ever: the first time it is asked after a finished round once
## the player has played HOURS_BEFORE_THANKS in all (`played_s`, PlayerStats'
## clock by default). Never again after that.
static func thank_once(path := SEEN_PATH, played_s := -1.0) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	if cfg.get_value("support", "thanked", false):
		return false
	if (played_s if played_s >= 0.0 else PlayerStats.play_seconds()) < HOURS_BEFORE_THANKS * 3600.0:
		return false
	cfg.set_value("support", "thanked", true)
	cfg.save(path)
	return true


## Opens the page in the browser (a new tab in the web build).
static func open() -> void:
	OS.shell_open(URL)
