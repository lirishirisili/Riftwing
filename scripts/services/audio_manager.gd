extends Node
## Layered sound-hook facade (autoload).
##
## Central place gameplay routes sound intents through, so priorities and volume
## groups live in one spot (docs/04_ARCHITECTURE.md). No audio assets ship with
## the prototype, so play_sfx() is a wired hook: it records the request and will
## trigger a pooled AudioStreamPlayer once banks exist.
##
## Audio focus: when the app backgrounds, set_has_focus(false) ducks/silences
## playback so mobile OS audio-focus rules are respected even before real banks
## land. Master `enabled` remains the settings toggle.

const PRIORITY_LOW := 0
const PRIORITY_MEDIUM := 1
const PRIORITY_HIGH := 2

## Master enable so a pause menu / settings can silence audio without touching
## gameplay code. Prototype default: on.
var enabled: bool = true
## False while the app is backgrounded / lost audio focus.
var has_focus: bool = true

var last_sfx: String = ""
var last_priority: int = PRIORITY_LOW
var sfx_count: int = 0
var _per_cue: Dictionary = {}
var _focus_blocked: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## App lifecycle calls this on pause/resume so SFX never play in the background.
func set_has_focus(focused: bool) -> void:
	has_focus = focused


func play_sfx(cue: String, _world_pos: Vector2 = Vector2.ZERO, priority: int = PRIORITY_LOW) -> void:
	if not enabled:
		return
	if not has_focus:
		_focus_blocked += 1
		return
	last_sfx = cue
	last_priority = priority
	sfx_count += 1
	_per_cue[cue] = int(_per_cue.get(cue, 0)) + 1


func cue_count(cue: String) -> int:
	return int(_per_cue.get(cue, 0))


func distinct_cues() -> int:
	return _per_cue.size()


func focus_blocked_count() -> int:
	return _focus_blocked
