class_name SettingsScreen
extends Control
## Settings screen reachable from the main menu's gear button.
##
## Exposes the options the prototype can honestly back today: master audio
## (AudioManager.enabled), effects quality (GameFeel LOW/MED/HIGH, persisted),
## a haptics toggle (persisted and honored by GameFeel), and a two-tap Reset
## Progress that clears the SaveManager.

const _BASE_PADDING := 56.0

@onready var _safe: MarginContainer = %Safe
@onready var _audio_button: Button = %AudioButton
@onready var _quality_button: Button = %QualityButton
@onready var _haptics_button: Button = %HapticsButton
@onready var _reset_button: Button = %ResetButton
@onready var _reset_hint: Label = %ResetHint
@onready var _back: Button = %BackButton

var _reset_armed := false


func _ready() -> void:
	_audio_button.pressed.connect(_on_audio)
	_quality_button.pressed.connect(_on_quality)
	_haptics_button.pressed.connect(_on_haptics)
	_reset_button.pressed.connect(_on_reset)
	_back.pressed.connect(_on_back)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh()


func _refresh() -> void:
	_audio_button.text = "AUDIO:  %s" % ("ON" if AudioManager.enabled else "OFF")
	_quality_button.text = "EFFECTS:  %s" % GameFeel.quality_name()
	_haptics_button.text = "HAPTICS:  %s" % ("ON" if GameFeel.haptics_enabled else "OFF")
	_reset_button.text = "RESET PROGRESS?  TAP AGAIN" if _reset_armed else "RESET PROGRESS"
	_reset_hint.text = "Rift Energy %d · Rift Core %d · Best %d" % [
		SaveManager.get_rift_energy(), SaveManager.get_rift_core(), SaveManager.get_best_score()]


func _on_audio() -> void:
	AudioManager.enabled = not AudioManager.enabled
	_click()
	_refresh()


func _on_quality() -> void:
	GameFeel.cycle_quality()
	_click()
	_refresh()


func _on_haptics() -> void:
	GameFeel.set_haptics_enabled(not GameFeel.haptics_enabled)
	_click()
	_refresh()


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_click()
		_refresh()
		return
	SaveManager.reset()
	_reset_armed = false
	_click()
	_refresh()


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if GameFeel.haptics_enabled and haptics != null:
		haptics.light()


func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	_safe.add_theme_constant_override("margin_bottom", int(_BASE_PADDING + (full.y - (safe.position.y + safe.size.y))))
