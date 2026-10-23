class_name GameplayHUD
extends Control
## Production in-run HUD: score, currency, wave/boss slot, pause, vitals, abilities.
##
## Presentation only — does not alter combat resolution. Bottom vitals use
## angular chrome + hex level; XP reads as a purple shield-slot style without
## adding a shield combat system. Ability buttons emit feedback hooks only.

signal pause_requested()
signal resume_requested()
signal quit_to_menu_requested()
signal ability_left_activated()
signal ability_right_activated()
signal nova_activated()

const _RULES_PATH := "res://resources/progression/reward_rules_default.tres"
const _ICON_MISSILE := "res://assets/icons/icon_missile.svg"
const _ICON_LASER := "res://assets/icons/icon_laser.svg"

@onready var _safe: MarginContainer = $Safe
@onready var _score_value: Label = $Safe/Root/Top/ScoreChip/VBox/ScoreValue
@onready var _currency_value: Label = $Safe/Root/Top/ScoreChip/VBox/CurrencyRow/CurrencyValue
@onready var _currency_chip: PanelContainer = $Safe/Root/Top/ScoreChip
@onready var _wave_panel: PanelContainer = $Safe/Root/Top/WaveChip
@onready var _wave_label: Label = $Safe/Root/Top/WaveChip/WaveLabel
@onready var _combo_label: Label = $Safe/Root/Top/PauseCol/ComboLabel
@onready var _pause_btn: Button = $Safe/Root/Top/PauseCol/PauseShell/PauseButton
@onready var _health_bar: HudSegmentedBar = $Safe/Root/Bottom/Vitals/Content/VitalsRow/Bars/HealthBar
@onready var _energy_bar: HudSegmentedBar = $Safe/Root/Bottom/Vitals/Content/VitalsRow/XpCol/EnergyBar
@onready var _health_label: Label = $Safe/Root/Bottom/Vitals/Content/VitalsRow/Bars/HealthMeta/HealthValue
@onready var _energy_label: Label = $Safe/Root/Bottom/Vitals/Content/VitalsRow/XpCol/EnergyMeta/EnergyValue
@onready var _level_badge: Label = $Safe/Root/Bottom/Vitals/Content/VitalsRow/LevelBadge/LevelCol/LevelValue
@onready var _ability_left: AbilityButton = $Safe/Root/Bottom/AbilityLeft
@onready var _ability_right: AbilityButton = $Safe/Root/Bottom/AbilityRight
@onready var _pause_overlay: Control = $PauseOverlay
@onready var _resume_btn: GlowCtaButton = %ResumeButton
@onready var _quit_btn: GlowCtaButton = %QuitButton

var _player: PlayerShip
var _xp: ExperienceTracker
var _stats: RunStats
var _rules: RewardRulesData
var _boss_bar_visible: bool = false
var _currency_flash: float = 0.0
var _last_energy: int = -1
var _paused_by_hud: bool = false
## Quit requires a confirming second tap so an in-progress run is never lost by
## a single mis-tap. Reset whenever the overlay opens/closes.
var _quit_armed: bool = false
var _quit_title_default: String = "QUIT"
## Optional veto set by the run host: returns false while another modal (the
## upgrade cards) owns the tree pause, so Escape cannot unpause under it.
var pause_gate: Callable = Callable()
var _last_combo: int = -1
var _last_score: int = -1
var _icon_left: Texture2D
var _icon_right: Texture2D
var _nova: NovaButton
var _callout: Label
var _callout_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules = load(_RULES_PATH) as RewardRulesData
	if _rules == null:
		_rules = RewardRulesData.new()
	_pause_overlay.visible = false
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	# Keep vitals/abilities frozen with the tree; only the pause chrome stays live.
	_safe.process_mode = Node.PROCESS_MODE_PAUSABLE
	_pause_btn.pressed.connect(_on_pause_pressed)
	_resume_btn.pressed.connect(_on_resume_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	if _quit_btn.title != "":
		_quit_title_default = _quit_btn.title
	_icon_left = load(_ICON_MISSILE) as Texture2D
	_icon_right = load(_ICON_LASER) as Texture2D
	configure_abilities(3, 7.0, 2, 9.0)
	_ability_left.activated.connect(func() -> void: ability_left_activated.emit())
	_ability_right.activated.connect(func() -> void: ability_right_activated.emit())
	_build_nova_button()
	_build_callout()
	_health_bar.set_fill_color(Palette.get_color("cyan"))
	_energy_bar.set_fill_color(Palette.get_color("purple"))
	_energy_bar.low_threshold = 0.0
	call_deferred("_refresh_currency_pivot")
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	set_process(true)


## Ability charges / recharge seconds come from RunRulesData via the run host.
func configure_abilities(left_charges: int, left_cooldown: float, right_charges: int, right_cooldown: float) -> void:
	_ability_left.configure(left_charges, left_cooldown, _icon_left, Palette.get_color("cyan"))
	_ability_right.configure(right_charges, right_cooldown, _icon_right, Palette.get_color("purple"))


func _build_nova_button() -> void:
	_nova = NovaButton.new()
	_nova.name = "NovaButton"
	_nova.process_mode = Node.PROCESS_MODE_PAUSABLE
	_nova.ring_color = Palette.get_color("cyan", Color(0.0, 0.84, 1.0))
	_nova.activated.connect(func() -> void: nova_activated.emit())
	add_child(_nova)


func _build_callout() -> void:
	_callout = Label.new()
	_callout.name = "Callout"
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout.add_theme_font_size_override("font_size", 64)
	_callout.add_theme_constant_override("outline_size", 10)
	_callout.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
	_callout.visible = false
	add_child(_callout)


## Big center-top text pop for streaks, level-ups, evolutions, Nova, etc.
## `subtitle` renders on a second line.
func show_callout(text: String, color: Color, subtitle: String = "", seconds: float = 1.2) -> void:
	if _callout == null:
		return
	_callout.text = text if subtitle == "" else "%s\n%s" % [text, subtitle]
	_callout.modulate = color
	_callout.visible = true
	_callout.pivot_offset = _callout.size * 0.5
	_callout.scale = Vector2(1.6, 1.6)
	if _callout_tween != null and _callout_tween.is_valid():
		_callout_tween.kill()
	_callout_tween = create_tween()
	_callout_tween.tween_property(_callout, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_callout_tween.tween_interval(maxf(0.1, seconds - 0.5))
	_callout_tween.tween_property(_callout, "modulate:a", 0.0, 0.28)
	_callout_tween.tween_callback(func() -> void: _callout.visible = false)


## Rift Nova charge 0..1 (1 = ready).
func set_nova_charge(fraction: float) -> void:
	if _nova != null:
		_nova.set_charge(fraction)


func get_nova_button() -> NovaButton:
	return _nova


func _refresh_currency_pivot() -> void:
	if _currency_chip != null:
		_currency_chip.pivot_offset = _currency_chip.size * 0.5


## Called once the run host has player / XP / stats ready.
func bind(player: PlayerShip, xp: ExperienceTracker, stats: RunStats) -> void:
	if _player != null and _player.health_changed.is_connected(_on_health_changed):
		_player.health_changed.disconnect(_on_health_changed)
	if _player != null and _player.energy_changed.is_connected(_on_energy_changed):
		_player.energy_changed.disconnect(_on_energy_changed)
	if _xp != null and _xp.progress_changed.is_connected(_on_xp_changed):
		_xp.progress_changed.disconnect(_on_xp_changed)
	_player = player
	_xp = xp
	_stats = stats
	_last_score = -1
	_last_combo = -1
	if _player != null:
		_player.health_changed.connect(_on_health_changed)
		_player.energy_changed.connect(_on_energy_changed)
		_on_health_changed(_player.get_health(), _player.combat_data.max_health)
		_on_energy_changed(_player.get_energy())
	if _xp != null:
		_xp.progress_changed.connect(_on_xp_changed)
		_on_xp_changed(_xp.get_level(), _xp.get_xp_into_level(), _xp.get_xp_for_next())
	_refresh_score()


func set_wave_info(text: String) -> void:
	_wave_label.text = text


func set_boss_bar_visible(active: bool) -> void:
	_boss_bar_visible = active
	_wave_panel.visible = not active


func set_combo(combo: int) -> void:
	if combo == _last_combo:
		return
	var rising := combo > _last_combo
	_last_combo = combo
	if combo >= 2:
		_combo_label.text = "x%d" % combo
		var heat := clampf(float(combo - 2) / 18.0, 0.0, 1.0)
		if combo >= 15:
			_combo_label.modulate = Palette.get_color("gold", Color(1, 0.84, 0.25))
		elif combo >= 10:
			_combo_label.modulate = Palette.get_color("purple", Color(0.75, 0.4, 1.0))
		elif combo >= 5:
			_combo_label.modulate = Palette.get_color("orange", Color(1, 0.55, 0.2))
		else:
			_combo_label.modulate = Color(1, 1, 1, 1)
		# Brief scale pop on milestone combos.
		if rising and combo >= 5 and combo % 5 == 0:
			_combo_label.pivot_offset = _combo_label.size * 0.5
			_combo_label.scale = Vector2(1.35 + heat * 0.15, 1.35 + heat * 0.15)
			var tw := create_tween()
			tw.tween_property(_combo_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)
	else:
		_combo_label.text = ""
		_combo_label.modulate = Color(1, 1, 1, 1)
		_combo_label.scale = Vector2.ONE


func is_hud_paused() -> bool:
	return _paused_by_hud


## Opens the pause overlay (no-op if already paused). Used by system Back and
## by the run host when the app is backgrounded.
func request_pause() -> void:
	if not _pause_allowed():
		return
	_on_pause_pressed()


func _pause_allowed() -> bool:
	return not pause_gate.is_valid() or bool(pause_gate.call())


## Toggle pause/resume — Escape / pause action / Android Back while paused.
func toggle_pause() -> void:
	if _paused_by_hud:
		_on_resume_pressed()
	elif _pause_allowed():
		_on_pause_pressed()


func force_resume() -> void:
	if _paused_by_hud:
		_on_resume_pressed()


func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport().get_visible_rect().size
	_safe.add_theme_constant_override("margin_left", int(maxi(16, int(safe.position.x) + 12)))
	_safe.add_theme_constant_override("margin_top", int(maxi(12, int(safe.position.y) + 8)))
	_safe.add_theme_constant_override("margin_right", int(maxi(16, int(full.x - safe.end.x) + 12)))
	_safe.add_theme_constant_override("margin_bottom", int(maxi(18, int(full.y - safe.end.y) + 14)))
	_layout_overlays(safe, full)


## Places the Nova orb above the right ability button and the callout under the
## top chips, both inside the safe area.
func _layout_overlays(safe: Rect2, full: Vector2) -> void:
	var right := maxf(16.0, full.x - safe.end.x + 12.0)
	var bottom := maxf(18.0, full.y - safe.end.y + 14.0)
	if _nova != null:
		_nova.position = Vector2(full.x - right - _nova.size.x - 4.0, full.y - bottom - 112.0 - 28.0 - _nova.size.y)
	if _callout != null:
		_callout.position = Vector2(0.0, safe.position.y + full.y * 0.2)
		_callout.size = Vector2(full.x, 200.0)


func _process(delta: float) -> void:
	if _currency_flash > 0.0:
		_currency_flash = maxf(0.0, _currency_flash - delta * 3.0)
		var pulse := 1.0 + _currency_flash * 0.08
		_currency_chip.scale = Vector2(pulse, pulse)
	_refresh_score()


func _refresh_score() -> void:
	if _stats == null or _rules == null or _score_value == null:
		return
	# `_stats.rift_energy_collected` is kept in sync by `_on_energy_changed`, so the
	# HUD and the results screen read one shared score value.
	var score := _stats.live_score(_rules)
	if score == _last_score:
		return
	_last_score = score
	_score_value.text = _format_score(score)


func _format_score(value: int) -> String:
	var s := str(maxi(0, value))
	var out := ""
	var i := s.length()
	while i > 0:
		var start := maxi(0, i - 3)
		var chunk := s.substr(start, i - start)
		out = chunk + out if out.is_empty() else chunk + "," + out
		i = start
	return out


func _on_health_changed(current: float, maximum: float) -> void:
	var frac := 0.0 if maximum <= 0.0 else current / maximum
	_health_bar.set_fraction(frac)
	_health_label.text = "%d" % int(ceili(current))


func _on_energy_changed(total: int) -> void:
	_currency_value.text = str(total)
	if _last_energy >= 0 and total > _last_energy:
		_currency_flash = 1.0
	_last_energy = total
	# Settled runs are frozen: loot landing after the end must not edit them.
	if _stats != null and not _stats.settled:
		_stats.rift_energy_collected = total


func _on_xp_changed(level: int, xp_into: int, xp_for_next: int) -> void:
	_level_badge.text = str(level)
	var frac := 1.0 if xp_for_next <= 0 else float(xp_into) / float(xp_for_next)
	_energy_bar.set_fraction(clampf(frac, 0.0, 1.0))
	_energy_label.text = "%d/%d" % [xp_into, xp_for_next]


func _on_pause_pressed() -> void:
	if _paused_by_hud:
		return
	_paused_by_hud = true
	_reset_quit_arm()
	_pause_overlay.visible = true
	get_tree().paused = true
	AudioManager.set_fire_loop_suppressed(true)
	AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	pause_requested.emit()


func _on_resume_pressed() -> void:
	if not _paused_by_hud:
		return
	_paused_by_hud = false
	_reset_quit_arm()
	_pause_overlay.visible = false
	get_tree().paused = false
	AudioManager.set_fire_loop_suppressed(false)
	AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	resume_requested.emit()


func _on_quit_pressed() -> void:
	# First tap arms the confirmation; the run keeps running (still paused) so an
	# accidental tap never discards progress. Second tap actually quits.
	if not _quit_armed:
		_quit_armed = true
		_quit_btn.title = "CONFIRM QUIT"
		_quit_btn.subtitle = "Run progress is lost"
		AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
		return
	_reset_quit_arm()
	_paused_by_hud = false
	_pause_overlay.visible = false
	get_tree().paused = false
	AudioManager.set_fire_loop_suppressed(false)
	AudioManager.stop_fire_loop()
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	quit_to_menu_requested.emit()


func _reset_quit_arm() -> void:
	_quit_armed = false
	if _quit_btn != null:
		_quit_btn.title = _quit_title_default
		_quit_btn.subtitle = ""


func _unhandled_input(event: InputEvent) -> void:
	# Escape / mapped pause only. Android system Back is handled in AppRoot via
	# NOTIFICATION_WM_GO_BACK_REQUEST so we never double-toggle with KEY_BACK.
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
