class_name MainMenu
extends Control
## Production RIFTSTRIKE home screen (prompts/17_main_menu_production.md).
##
## Cinematic key art + parallax, tech header chrome, hex CTAs, holo pad hero.
## Navigation:
##   Start Run       -> stage map
##   Daily Challenge -> daily challenge hub
##   Event banner    -> VOID INVASION event hub
##   Ships / Upgrades-> hangar
##   Settings        -> settings

const _BASE_PADDING := 36.0
const _BASE_PADDING_BOTTOM := 88.0
## Extra bottom reserve (logical px) so the LevelPlay banner overlay never
## covers the START/DAILY/SHIPS/UPGRADES CTAs. Only applied when ads are live.
const _BANNER_RESERVE := 168.0
const _SCROLL_SPEED := 14.0
const _CATALOG_PATH := "res://resources/ships/ship_catalog_default.tres"
const _VANGUARD_HERO_PATH := "res://assets/art/ships/hero_vanguard_menu.png"
const _CAPTURE_SIZE := Vector2i(1080, 1920)
const _CAPTURE_PATH := "user://riftwing_main_menu_1080x1920.png"
const _EVENT_PATH := "res://resources/events/void_invasion.tres"

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
@onready var _start_button: GlowCtaButton = %StartButton
@onready var _daily_button: GlowCtaButton = %DailyButton
@onready var _ships_button: GlowCtaButton = %ShipsButton
@onready var _upgrades_button: GlowCtaButton = %UpgradesButton
@onready var _settings_button: Button = %SettingsButton
@onready var _event_banner: PanelContainer = %EventBanner
@onready var _event_timer: Label = %EventTimer
@onready var _atmos_a: TextureRect = %AtmosEnemyA
@onready var _atmos_b: TextureRect = %AtmosEnemyB
@onready var _title: Label = %Title
@onready var _brand_logo: TextureRect = %BrandLogo

var _hero_time := 0.0
var _catalog: ShipCatalogData
var _event: EventData
var _event_tick := 0.0


func _ready() -> void:
	_catalog = load(_CATALOG_PATH) as ShipCatalogData
	if _catalog == null:
		_catalog = ShipCatalogData.new()

	_start_button.configure("START RUN", "CAMPAIGN", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN)
	_daily_button.configure("DAILY CHALLENGE", "COMPLETE AND EARN REWARDS", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.MAGENTA)
	_ships_button.configure("HANGAR", "SHIPS · UPGRADES", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 104.0)
	# SHIPS already opens the hangar (ships + upgrades); this slot hosts the
	# extra modes instead of a second hangar entry.
	_upgrades_button.configure("MODES", "ENDLESS · RUSH", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 104.0)
	_daily_button.set_icons(
		load("res://assets/icons/icon_target.svg") as Texture2D,
		load("res://assets/icons/icon_chevron.svg") as Texture2D)
	_ships_button.set_icons(load("res://assets/icons/icon_nav_ship.svg") as Texture2D)
	_upgrades_button.set_icons(load("res://assets/icons/icon_boss.svg") as Texture2D)

	_start_button.pressed.connect(_on_start_run)
	_daily_button.pressed.connect(_on_daily_challenge)
	_ships_button.pressed.connect(_on_ships)
	_upgrades_button.pressed.connect(_on_upgrades)
	_build_progress_button()
	call_deferred("_maybe_show_privacy")
	_settings_button.pressed.connect(_on_settings)
	_event_banner.gui_input.connect(_on_event_gui_input)

	# Probe / hierarchy: primary taller than daily.
	_start_button.custom_minimum_size = Vector2(0, 156)
	_daily_button.custom_minimum_size = Vector2(0, 108)
	_ships_button.custom_minimum_size = Vector2(0, 104)
	_upgrades_button.custom_minimum_size = Vector2(0, 104)

	_event = load(_EVENT_PATH) as EventData
	_refresh_event_timer()

	SaveManager.currencies_changed.connect(_on_currencies_changed)
	SaveManager.hangar_changed.connect(_on_hangar_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_currencies()
	_refresh_profile()
	GameFeel.debug_markers_enabled = false
	AudioManager.play_music("menu")
	_request_banner()


## Shows the main-menu banner. The banner is a bottom-anchored native overlay
## and is the only surface allowed to show a banner. If LevelPlay has not
## finished initializing yet, it is shown once init succeeds.
func _request_banner() -> void:
	var ads: AdsService = PlatformServices.ads
	if ads == null or not ads.is_available():
		return
	ads.show_banner()
	# Re-layout when the banner settles so a failed banner leaves no empty gap.
	if not ads.banner_failed.is_connected(_on_banner_state_changed):
		ads.banner_failed.connect(_on_banner_state_changed)
	if not ads.banner_loaded.is_connected(_on_banner_loaded):
		ads.banner_loaded.connect(_on_banner_loaded)
	if not ads.initialization_finished.is_connected(_on_ads_initialized):
		ads.initialization_finished.connect(_on_ads_initialized, CONNECT_ONE_SHOT)


func _on_banner_state_changed(_message: String) -> void:
	if is_inside_tree():
		_apply_safe_area()


func _on_banner_loaded() -> void:
	if is_inside_tree():
		_apply_safe_area()


func _on_ads_initialized(success: bool) -> void:
	if success and is_inside_tree():
		PlatformServices.ads.show_banner()


func _exit_tree() -> void:
	# Hide the banner whenever we leave the menu so it never covers gameplay,
	# the hangar, upgrades, or any other screen.
	var ads: AdsService = PlatformServices.ads
	if ads != null:
		if ads.banner_failed.is_connected(_on_banner_state_changed):
			ads.banner_failed.disconnect(_on_banner_state_changed)
		if ads.banner_loaded.is_connected(_on_banner_loaded):
			ads.banner_loaded.disconnect(_on_banner_loaded)
		ads.hide_banner()


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
	var title_glow := 0.9 + sin(_hero_time * 0.85) * 0.1
	if _brand_logo != null:
		_brand_logo.modulate = Color(title_glow, title_glow, 1.0, 1.0)
	elif _title != null:
		_title.modulate = Color(title_glow, title_glow, 1.0, 1.0)
	_event_tick += delta
	if _event_tick >= 1.0:
		_event_tick = 0.0
		_refresh_event_timer()


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
	SceneRouter.go_to(SceneRouter.SCREEN_DAILY)


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
	SceneRouter.go_to(SceneRouter.SCREEN_EVENT)


func _on_ships() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR, {"return_to": SceneRouter.SCREEN_MAIN_MENU})


func _on_upgrades() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_MODES)


func _on_settings() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_SETTINGS)


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	GameFeel.haptic("light")


## Shows the real remaining time on the event banner (active window or next open).
func _refresh_event_timer() -> void:
	if _event_timer == null:
		return
	if _event == null:
		_event_timer.text = "SOON"
		return
	var now := int(Time.get_unix_time_from_system())
	var remaining := _event.remaining_seconds(now)
	if _event.is_active(now):
		_event_timer.text = EventData.format_countdown(remaining)
	else:
		_event_timer.text = "IN %s" % EventData.format_countdown(remaining)


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
		_profile_name.text = Brand.DISPLAY
		_hero_ship.modulate = Color(1, 1, 1, 1)
	# Pilot rank (real meta progression) replaces the old placeholder power bar.
	_profile_power.text = "PILOT LV %d" % MetaProgress.pilot_level()
	_power_bar.max_value = float(MetaProgress.xp_for_next())
	_power_bar.value = float(MetaProgress.pilot_xp())


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
	# Reserve room for the bottom banner overlay when ads are live so the native
	# banner never overlaps the CTA stack.
	var banner_reserve := 0.0
	var ads: AdsService = PlatformServices.ads
	if ads != null and ads.expects_banner():
		banner_reserve = _BANNER_RESERVE
	_safe.add_theme_constant_override(
		"margin_bottom",
		int(_BASE_PADDING_BOTTOM + bottom_inset + banner_reserve)
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


# --- Progress hub + welcome-back rewards ---------------------------------------------

const _GLOW_CTA := preload("res://scenes/ui/chrome/glow_cta_button.tscn")
var _progress_button: GlowCtaButton
var _welcome: Control


func _build_progress_button() -> void:
	var row := _ships_button.get_parent()
	if row == null:
		return
	_progress_button = _GLOW_CTA.instantiate() as GlowCtaButton
	_progress_button.name = "ProgressButton"
	_progress_button.size_flags_horizontal = _ships_button.size_flags_horizontal
	_progress_button.custom_minimum_size = _ships_button.custom_minimum_size
	row.add_child(_progress_button)
	_progress_button.set_icons(load("res://assets/icons/icon_target.svg") as Texture2D)
	_progress_button.pressed.connect(func() -> void:
		_click()
		SceneRouter.go_to(SceneRouter.SCREEN_PROGRESS))
	_refresh_progress_badge()


func _refresh_progress_badge() -> void:
	if _progress_button == null:
		return
	var n := MetaProgress.claimable_count()
	_progress_button.configure("PROGRESS", "%d TO CLAIM" % n if n > 0 else "MISSIONS · AWARDS",
		GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.MAGENTA if n > 0 else GlowCtaButton.Pulse.NONE, 104.0)


## Once per day (login streak) or after time away (patrol income), a modal
## summarizes the rewards waiting and claims them with one tap.
func _maybe_show_welcome() -> void:
	if not is_inside_tree() or _welcome != null:
		return
	var login := MetaProgress.login_status()
	var patrol := MetaProgress.patrol_pending()
	if not bool(login["can_claim"]) and patrol <= 0:
		return
	_welcome = Control.new()
	_welcome.name = "WelcomeBack"
	_welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_welcome)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NeonPanel"
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	col.add_child(_welcome_label("WELCOME BACK, PILOT", 46, Color(0.96, 0.98, 1)))
	if bool(login["can_claim"]):
		var today := int(login["day"])
		col.add_child(_welcome_label("LOGIN STREAK · DAY %d / 7" % today, 30, Color(1, 0.85, 0.4)))
		var days := HBoxContainer.new()
		days.add_theme_constant_override("separation", 6)
		days.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(days)
		for d in range(1, 8):
			var r := MetaProgress.login_reward(d)
			var box := PanelContainer.new()
			box.theme_type_variation = &"NeonPanel"
			box.custom_minimum_size = Vector2(112, 112)
			box.modulate = Color(1, 1, 1, 1) if d == today else (Color(0.55, 0.6, 0.7, 1) if d < today else Color(0.8, 0.85, 0.95, 0.8))
			var bl := _welcome_label("D%d\n%s" % [d, ("%d CORE" % int(r["core"])) if int(r["core"]) > 0 else ("%d" % int(r["energy"]))],
				20, Color(1, 0.85, 0.4) if d == today else Color(0.85, 0.9, 1))
			box.add_child(bl)
			days.add_child(box)
	if patrol > 0:
		var mins := int(MetaProgress.patrol_minutes())
		col.add_child(_welcome_label("PATROL EARNINGS  +%d RIFT ENERGY" % patrol, 30, Palette.get_color("cyan", Color(0.2, 0.9, 1))))
		col.add_child(_welcome_label("%dh %02dm on patrol (cap %dh)" % [mins / 60, mins % 60, int(MetaProgress.catalog().patrol_cap_hours)],
			22, Color(0.6, 0.72, 0.9)))
	var claim := _GLOW_CTA.instantiate() as GlowCtaButton
	col.add_child(claim)
	claim.configure("CLAIM", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 110.0)
	claim.pressed.connect(_claim_welcome)
	if patrol > 0 and RewardedAd.is_ready():
		var double := _GLOW_CTA.instantiate() as GlowCtaButton
		col.add_child(double)
		double.configure("CLAIM ×2 PATROL", "WATCH AN AD", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.MAGENTA, 96.0)
		double.pressed.connect(func() -> void:
			RewardedAd.show("patrol_double", func() -> void: _claim_welcome(2)))


func _welcome_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _claim_welcome(patrol_mult: int = 1) -> void:
	MetaProgress.claim_login()
	MetaProgress.claim_patrol(patrol_mult)
	AudioManager.play_sfx("reward", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	GameFeel.haptic("medium")
	if _welcome != null:
		_welcome.queue_free()
		_welcome = null
	_refresh_currencies()
	_refresh_progress_badge()


# --- First-launch privacy choice ---------------------------------------------------------

## Asked once, before ads start (PlatformServices waits for the answer).
func _maybe_show_privacy() -> void:
	if not is_inside_tree():
		return
	if PlatformServices.has_privacy_choice():
		_maybe_show_welcome()
		return
	var modal := Control.new()
	modal.name = "PrivacyChoice"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NeonPanel"
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	col.add_child(_welcome_label("YOUR PRIVACY", 46, Color(0.96, 0.98, 1)))
	var body := _welcome_label(
		"%s is free to play thanks to ads. May our ad partners use your device's advertising ID to show ads that match your interests? You can change this anytime in Settings." % Brand.DISPLAY,
		26, Color(0.82, 0.88, 1))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	var allow := _GLOW_CTA.instantiate() as GlowCtaButton
	col.add_child(allow)
	allow.configure("ALLOW PERSONALIZED ADS", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 104.0)
	allow.pressed.connect(_on_privacy_choice.bind(modal, true))
	var decline := _GLOW_CTA.instantiate() as GlowCtaButton
	col.add_child(decline)
	decline.configure("NON-PERSONALIZED ADS ONLY", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 92.0)
	decline.pressed.connect(_on_privacy_choice.bind(modal, false))
	var policy := Button.new()
	policy.text = "Privacy Policy"
	policy.flat = true
	policy.custom_minimum_size = Vector2(0, 64)
	policy.add_theme_font_size_override("font_size", 24)
	policy.add_theme_color_override("font_color", Palette.get_color("cyan", Color(0.2, 0.9, 1)))
	policy.pressed.connect(func() -> void: OS.shell_open(Brand.PRIVACY_POLICY_URL))
	col.add_child(policy)


func _on_privacy_choice(modal: Control, consent: bool) -> void:
	_click()
	PlatformServices.apply_privacy(consent)
	modal.queue_free()
	_request_banner()
	call_deferred("_maybe_show_welcome")
