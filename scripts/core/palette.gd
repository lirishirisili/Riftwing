extends Node
## Autoload that exposes the canonical Riftwing color tokens.
##
## Tokens are the single source of truth in manifests/color_tokens.json so the
## theme, gameplay, and UI stay in sync. Roles follow docs/01_VISUAL_DIRECTION.md.

const TOKENS_PATH := "res://manifests/color_tokens.json"

var _tokens: Dictionary = {}


func _ready() -> void:
	_load_tokens()


func _load_tokens() -> void:
	if not FileAccess.file_exists(TOKENS_PATH):
		push_warning("Palette: color token file missing at %s" % TOKENS_PATH)
		return
	var text := FileAccess.get_file_as_string(TOKENS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Palette: could not parse color tokens as an object")
		return
	_tokens = parsed


## Returns a token color by key, or the given fallback when the key is unknown.
func get_color(token: String, fallback: Color = Color.MAGENTA) -> Color:
	if _tokens.has(token):
		return Color.from_string(String(_tokens[token]), fallback)
	return fallback
