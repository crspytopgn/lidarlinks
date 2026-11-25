class_name Support
extends RefCounted
## Where people can chip in to keep LidarLinks going. The main menu's
## Support button and the quiet line under the final scorecard open it; the
## launcher (launcher/scripts/paths.gd SUPPORT_PAGE) and the README use the
## same page. Never a pop-up and never in the way of play.

const URL := "https://github.com/sponsors/crspytopgn"
const BUTTON := "Support"
const TOOLTIP := "LidarLinks is free, with no ads. This opens GitHub Sponsors in your browser, if you'd like to chip in."
const THANKS := "Enjoying LidarLinks? It's free and made in spare time. Support it"


## Opens the page in the browser (a new tab in the web build).
static func open() -> void:
	OS.shell_open(URL)
