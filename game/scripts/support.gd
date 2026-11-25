class_name Support
extends RefCounted
## Where people can chip in to keep LidarLinks going. The main menu's
## Support button opens it; the launcher (launcher/scripts/paths.gd
## SUPPORT_PAGE) and the README use the same page. Never a pop-up, and
## never in the way of play.

## Ko-fi first: it takes a card or PayPal with no account. GitHub Sponsors
## is the other way, linked from the README and the release notes.
const URL := "https://ko-fi.com/crspytopgn"
const SPONSORS_URL := "https://github.com/sponsors/crspytopgn"
const BUTTON := "Support"
const TOOLTIP := "LidarLinks is free, with no ads. This opens its Ko-fi page in your browser, if you'd like to chip in."


## Opens the page in the browser (a new tab in the web build).
static func open() -> void:
	OS.shell_open(URL)
