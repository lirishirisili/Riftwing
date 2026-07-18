class_name PlaceholderScreen
extends Control
## Generic "coming soon" screen for meta destinations not yet built.
##
## Ships, Upgrades (hangar), and Daily Challenge all route here through the
## SceneRouter with a title/subtitle payload, so the main menu's navigation is
## real and testable before those milestones exist (prompts/08_main_menu.md).
## The hangar, stage map, and daily systems are intentionally NOT implemented
## here — this only proves the navigation edge and offers a way back.

const _BASE_PADDING := 56.0

@onready var _safe: MarginContainer = %Safe
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _back: Button = %BackButton

var _pending_title := "COMING SOON"
var _pending_subtitle := "This feature arrives in a future update."


## Router handoff: title/subtitle for the destination this stands in for.
func receive_payload(payload: Dictionary) -> void:
	if payload.has("title"):
		_pending_title = String(payload["title"])
	if payload.has("subtitle"):
		_pending_subtitle = String(payload["subtitle"])


func _ready() -> void:
	_title.text = _pending_title
	_subtitle.text = _pending_subtitle
	_back.pressed.connect(_on_back)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


## Inset the content by the device safe area plus a base padding so the Back
## button and text never sit under a notch/cutout on any portrait ratio.
func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	_safe.add_theme_constant_override("margin_bottom", int(_BASE_PADDING + (full.y - (safe.position.y + safe.size.y))))
