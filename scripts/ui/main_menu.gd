class_name MainMenu
extends Control
## RIFTWING home screen (prompts/08_main_menu.md, docs/03_SCREEN_SPEC.md).
##
## Built from real Control nodes over a live parallax starfield — the reference
## image is visual direction only, never a shipped texture, and all text
## (branding, currencies, button labels) is real Godot UI. Layout is a top-to-
## bottom VBox whose hero area absorbs extra height, so composition holds across
## 9:16, 19.5:9, and 20:9. The Safe MarginContainer is inset from the device
## safe area at runtime so nothing sits under a notch/cutout.
##
## Navigation:
##   Start Run       -> galaxy map (stage select)
##   Daily Challenge -> placeholder (system owned by a later milestone)
##   Ships / Upgrades-> hangar (permanent ship upgrades)
##   Settings (gear) -> settings screen
## The daily system is intentionally NOT built here.

const _BASE_PADDING := 44.0
const _SCROLL_SPEED := 24.0
## Screenshot/debug capture size (docs/10: review images at 1080x1920).
const _CAPTURE_SIZE := Vector2i(1080, 1920)
const _CAPTURE_PATH := "user://riftwing_main_menu_1080x1920.png"

@onready var _parallax: ParallaxBackground = $Background
@onready var _safe: MarginContainer = %Safe
@onready var _energy_value: Label = %EnergyValue
@onready var _core_value: Label = %CoreValue
@onready var _hero_ship: TextureRect = %HeroShip
@onready var _start_button: Button = %StartButton
@onready var _daily_button: Button = %DailyButton
@onready var _ships_button: Button = %ShipsButton
@onready var _upgrades_button: Button = %UpgradesButton
@onready var _settings_button: Button = %SettingsButton

var _hero_time := 0.0


func _ready() -> void:
	_start_button.pressed.connect(_on_start_run)
	_daily_button.pressed.connect(_on_daily_challenge)
	_ships_button.pressed.connect(_on_ships)
	_upgrades_button.pressed.connect(_on_upgrades)
	_settings_button.pressed.connect(_on_settings)

	SaveManager.currencies_changed.connect(_on_currencies_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_currencies()


func _process(delta: float) -> void:
	# Slow drift keeps the home screen alive without pulling focus.
	_parallax.scroll_offset.y += delta * _SCROLL_SPEED
	# Gentle hero "breathing" so the ship reads as the focal point.
	_hero_time += delta
	var pulse := 1.0 + sin(_hero_time * 1.6) * 0.02
	_hero_ship.scale = Vector2(pulse, pulse)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot_capture"):
		_capture_screenshot()
		get_viewport().set_input_as_handled()


# --- Navigation -------------------------------------------------------------

func _on_start_run() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_STAGE_MAP)


func _on_daily_challenge() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_PLACEHOLDER, {
		"title": "DAILY CHALLENGE",
		"subtitle": "Daily runs with modifiers arrive in a future update.",
	})


func _on_ships() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR)


func _on_upgrades() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR)


func _on_settings() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_SETTINGS)


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.light()


# --- Currencies -------------------------------------------------------------

func _on_currencies_changed(_energy: int, _core: int) -> void:
	_refresh_currencies()


func _refresh_currencies() -> void:
	_energy_value.text = _format_int(SaveManager.get_rift_energy())
	_core_value.text = _format_int(SaveManager.get_rift_core())


func _format_int(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


# --- Layout / capture -------------------------------------------------------

## Inset content by the device safe area plus a base padding on every portrait
## ratio, recomputed whenever the viewport resizes.
func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	_safe.add_theme_constant_override("margin_bottom", int(_BASE_PADDING + (full.y - (safe.position.y + safe.size.y))))


## Screenshot/debug mode: hide any debug UI, force a 1080x1920 window, wait for
## a clean frame, save a PNG, then restore. Used for reference comparison.
func _capture_screenshot() -> void:
	var tree := get_tree()
	var debuggers := tree.get_nodes_in_group("debug_ui")
	var restore: Array = []
	for node in debuggers:
		# CanvasItem and CanvasLayer both expose "visible"; hide either kind.
		if "visible" in node:
			restore.append([node, node.visible])
			node.visible = false

	var prev_size := DisplayServer.window_get_size()
	DisplayServer.window_set_size(_CAPTURE_SIZE)
	await tree.process_frame
	await tree.process_frame

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_CAPTURE_PATH)
	if err != OK:
		push_warning("MainMenu: screenshot save failed (%d)" % err)
	else:
		print("MainMenu: saved %dx%d screenshot to %s" % [
			image.get_width(), image.get_height(), _CAPTURE_PATH])

	DisplayServer.window_set_size(prev_size)
	for entry in restore:
		entry[0].visible = entry[1]
