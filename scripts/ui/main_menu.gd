class_name MainMenu
extends Control
## Production RIFTWING home screen (prompts/17_main_menu_production.md).
##
## Cinematic key art + parallax, tech header chrome, hex CTAs, holo pad hero.
## Navigation is unchanged:
##   Start Run       -> stage map
##   Daily Challenge -> placeholder (later milestone)
##   Event banner    -> same placeholder route
##   Ships / Upgrades-> hangar
##   Settings        -> settings
## No monetization or online systems.

const _BASE_PADDING := 36.0
const _BASE_PADDING_BOTTOM := 88.0
const _SCROLL_SPEED := 14.0
const _CATALOG_PATH := "res://resources/ships/ship_catalog_default.tres"
const _VANGUARD_HERO_PATH := "res://assets/art/ships/hero_vanguard_menu.png"
const _CAPTURE_SIZE := Vector2i(1080, 1920)
const _CAPTURE_PATH := "user://riftwing_main_menu_1080x1920.png"
const _EVENT_TIMER_COPY := "2D 14H"

@onready var _parallax: ParallaxBackground = $Background
@onready var _safe: MarginContainer = %Safe
@onready var _energy_value: Label = %EnergyValue
@onready var _core_value: Label = %CoreValue
@onready var _profile_name: Label = %ProfileName
@onready var _profile_power: Label = %ProfilePower
@onready var _power_bar: ProgressBar = %PowerBar
@onready var _hero_ship: TextureRect = %HeroShip
@onready var _engine_glow: TextureRect = %EngineGlow
@onready var _planet_accent: TextureRect = %PlanetAccent
@onready var _holo_pad: TextureRect = %HoloPad
@onready var _start_button: Button = %StartButton
@onready var _daily_button: Button = %DailyButton
@onready var _ships_button: Button = %ShipsButton
@onready var _upgrades_button: Button = %UpgradesButton
@onready var _settings_button: Button = %SettingsButton
@onready var _event_banner: PanelContainer = %EventBanner
@onready var _event_timer: Label = %EventTimer
@onready var _start_slot: Control = %StartSlot
@onready var _start_chrome: TextureRect = %StartChrome
@onready var _daily_chrome: TextureRect = %DailyChrome
@onready var _atmos_a: TextureRect = %AtmosEnemyA
@onready var _atmos_b: TextureRect = %AtmosEnemyB
@onready var _title: Label = %Title
@onready var _brand_logo: TextureRect = %BrandLogo

var _hero_time := 0.0
var _catalog: ShipCatalogData


func _ready() -> void:
	_catalog = load(_CATALOG_PATH) as ShipCatalogData
	if _catalog == null:
		_catalog = ShipCatalogData.new()

	_start_button.pressed.connect(_on_start_run)
	_daily_button.pressed.connect(_on_daily_challenge)
	_ships_button.pressed.connect(_on_ships)
	_upgrades_button.pressed.connect(_on_upgrades)
	_settings_button.pressed.connect(_on_settings)
	_event_banner.gui_input.connect(_on_event_gui_input)

	# Probe / hierarchy: primary taller than daily; slots own chrome size.
	_start_button.custom_minimum_size = Vector2(0, 156)
	_daily_button.custom_minimum_size = Vector2(0, 108)
	_ships_button.custom_minimum_size = Vector2(0, 104)
	_upgrades_button.custom_minimum_size = Vector2(0, 104)

	if _event_timer != null:
		_event_timer.text = _EVENT_TIMER_COPY

	SaveManager.currencies_changed.connect(_on_currencies_changed)
	SaveManager.hangar_changed.connect(_on_hangar_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_currencies()
	_refresh_profile()
	GameFeel.debug_markers_enabled = false
	AudioManager.play_music("menu")


func _process(delta: float) -> void:
	_parallax.scroll_offset.y += delta * _SCROLL_SPEED
	_hero_time += delta
	var breathe := 1.0 + sin(_hero_time * 1.35) * 0.018
	_hero_ship.scale = Vector2(breathe, breathe)
	_hero_ship.rotation = sin(_hero_time * 0.55) * 0.035
	_engine_glow.scale = Vector2(1.05 + sin(_hero_time * 3.2) * 0.1, 1.15 + sin(_hero_time * 2.4) * 0.08)
	_engine_glow.modulate.a = 0.68 + sin(_hero_time * 3.0) * 0.22
	if _holo_pad != null:
		var holo := 0.72 + sin(_hero_time * 1.4) * 0.18
		_holo_pad.modulate = Color(0.55, 0.95, 1.0, holo)
		_holo_pad.scale = Vector2(1.0 + sin(_hero_time * 1.2) * 0.035, 1.0 + sin(_hero_time * 1.2) * 0.02)
	_planet_accent.rotation = sin(_hero_time * 0.2) * 0.025
	_planet_accent.modulate.a = 0.48 + sin(_hero_time * 0.5) * 0.08
	_atmos_a.position.y = sin(_hero_time * 0.4) * 14.0
	_atmos_b.position.y = cos(_hero_time * 0.35) * 18.0
	_atmos_a.modulate.a = 0.28 + sin(_hero_time * 0.9) * 0.06
	_atmos_b.modulate.a = 0.22 + cos(_hero_time * 0.75) * 0.05
	var banner_pulse := 0.92 + sin(_hero_time * 1.1) * 0.08
	_event_banner.modulate = Color(banner_pulse, banner_pulse, 1.0, 1.0)
	var cta_glow := 0.92 + absf(sin(_hero_time * 1.8)) * 0.08
	if _start_chrome != null:
		_start_chrome.modulate = Color(cta_glow, cta_glow, 1.0, 1.0)
	if _daily_chrome != null:
		var daily_glow := 0.94 + absf(sin(_hero_time * 1.35)) * 0.06
		_daily_chrome.modulate = Color(1.0, daily_glow, 1.0, 1.0)
	if _start_slot != null:
		_start_slot.modulate = Color(1, 1, 1, 1)
	var title_glow := 0.9 + sin(_hero_time * 0.85) * 0.1
	if _brand_logo != null:
		_brand_logo.modulate = Color(title_glow, title_glow, 1.0, 1.0)
	elif _title != null:
		_title.modulate = Color(title_glow, title_glow, 1.0, 1.0)


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


func _on_event_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_event_pressed()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_on_event_pressed()


func _on_event_pressed() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_PLACEHOLDER, {
		"title": "VOID INVASION",
		"subtitle": "Event details arrive in a future update.",
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
	if haptics != null and GameFeel.haptics_enabled:
		haptics.light()


# --- Currencies / profile ---------------------------------------------------

func _on_currencies_changed(_energy: int, _core: int) -> void:
	_refresh_currencies()


func _on_hangar_changed(_ship_id: String) -> void:
	_refresh_profile()


func _refresh_currencies() -> void:
	_energy_value.text = _format_int(SaveManager.get_rift_energy())
	_core_value.text = _format_int(SaveManager.get_rift_core())


func _refresh_profile() -> void:
	var ship := _catalog.find_by_id(SaveManager.get_selected_ship_id())
	var levels := {}
	# Menu hero is a dedicated cinematic plate; never fall back to hangar SVG.
	_hero_ship.texture = load(_VANGUARD_HERO_PATH) as Texture2D
	if ship != null:
		levels = SaveManager.get_upgrade_levels(ship.id)
		_profile_name.text = String(ship.display_name).to_upper()
		_hero_ship.modulate = ship.accent_modulate
	else:
		_profile_name.text = "RIFTWING"
		_hero_ship.modulate = Color(1, 1, 1, 1)
	var power := StageProgress.player_power_from(ship, levels)
	_profile_power.text = "PWR  %d" % power
	var invested := 0
	var cap := 20
	for key in levels.keys():
		invested += int(levels[key])
	_power_bar.max_value = float(cap)
	_power_bar.value = float(mini(cap, invested + 4))


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

func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	# Extra bottom pad so SHIPS/UPGRADES never clip the home indicator / viewport edge.
	var bottom_inset := full.y - (safe.position.y + safe.size.y)
	# Hard cap — never let a bogus safe-area inset crush the CTA stack.
	bottom_inset = clampf(bottom_inset, 0.0, 96.0)
	_safe.add_theme_constant_override(
		"margin_bottom",
		int(_BASE_PADDING_BOTTOM + bottom_inset)
	)
	call_deferred("_recenter_hero_pivot")



func _recenter_hero_pivot() -> void:
	if _hero_ship == null:
		return
	_hero_ship.pivot_offset = _hero_ship.size * 0.5
	if _engine_glow != null:
		_engine_glow.pivot_offset = _engine_glow.size * 0.5
	if _planet_accent != null:
		_planet_accent.pivot_offset = _planet_accent.size * 0.5
	if _holo_pad != null:
		_holo_pad.pivot_offset = _holo_pad.size * 0.5


func _capture_screenshot() -> void:
	var tree := get_tree()
	var debuggers := tree.get_nodes_in_group("debug_ui")
	var restore: Array = []
	for node in debuggers:
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
