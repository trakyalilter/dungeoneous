class_name GameLog
extends RefCounted
## Event queue between game logic and UI.
## Logic calls GameLog.say() for log lines and GameLog.event() for things to animate
## (attack, damage, heal...). The UI drains them in order with take_events().

const GREEN := "#6ee36e"
const RED := "#ff6b6b"
const YELLOW := "#ffd84d"
const CYAN := "#5fd7ff"
const MAGENTA := "#e07bff"
const BLUE := "#7d9dff"
const GRAY := "#9a9a9a"

static var events: Array[Dictionary] = []
static var quiet := false  # mute everything (tests, bot simulation)
## Party slot of the hero the next events are about (0 in single player). Every event is stamped with it,
## so in co-op the stage knows which hero attacks, gets hit or levels up.
static var slot := 0


static func say(text: String, hex: String = "") -> void:
	event({"type": "log", "text": color(hex, text) if hex != "" else text})


static func event(data: Dictionary) -> void:
	if not quiet:
		if not data.has("slot"):
			data["slot"] = slot
		events.append(data)


static func take_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


static func clear() -> void:
	events.clear()


static func color(hex: String, text: String) -> String:
	return "[color=%s]%s[/color]" % [hex, text]


## Escape user text so "[" is not read as a BBCode tag.
static func esc(text: String) -> String:
	return text.replace("[", "[lb]")
