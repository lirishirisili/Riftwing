class_name StageMapScreen
extends Control
## Galaxy map / stage select (prompts/10_stage_map.md, docs/03_SCREEN_SPEC.md).
##
## Data-driven mission nodes from StageMapData, connected paths, locked states,
## star ratings, mission detail panel, NORMAL/HARD difficulty (HARD locked), and
## Launch into a real run. Branding reads RIFTWING; the reference image is visual
## direction only.

const _MAP_PATH := "res://resources/stages/nova_sector_map.tres"
const _BASE_PADDING := 36.0
const _NODE_RADIUS := 44.0
const _MAP_HEIGHT := 1180.0

@onready var _safe: MarginContainer = %Safe
@onready var _energy_value: Label = %EnergyValue
@onready var _core_value: Label = %CoreValue
@onready var _sector_label: Label = %SectorLabel
@onready var _map_canvas: Control = %MapCanvas
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_enemy: Label = %DetailEnemy
@onready var _detail_objective: Label = %DetailObjective
@onready var _power_recommended: Label = %PowerRecommended
@onready var _power_yours: Label = %PowerYours
@onready var _rewards_label: Label = %RewardsLabel
@onready var _first_clear_label: Label = %FirstClearLabel
@onready var _stars_label: Label = %StarsLabel
@onready var _lock_label: Label = %LockLabel
@onready var _launch_button: Button = %LaunchButton
@onready var _normal_button: Button = %NormalButton
@onready var _hard_button: Button = %HardButton
@onready var _back_button: Button = %BackButton
@onready var _hangar_button: Button = %HangarButton
@onready var _feedback_label: Label = %FeedbackLabel

var _map: StageMapData
var _selected_id: String = ""
var _node_buttons: Dictionary = {} # stage_id -> Button
var _feedback_tween: Tween


func receive_payload(payload: Dictionary) -> void:
	if payload.has("stage_id"):
		_selected_id = String(payload["stage_id"])


func _ready() -> void:
	_map = load(_MAP_PATH) as StageMapData
	if _map == null:
		_map = StageMapData.new()

	if _selected_id == "":
		_selected_id = SaveManager.get_selected_stage_id()
	if _map.find_by_id(_selected_id) == null:
		_selected_id = _map.default_stage_id()

	_back_button.pressed.connect(_on_back)
	_hangar_button.pressed.connect(_on_hangar)
	_launch_button.pressed.connect(_on_launch)
	_normal_button.pressed.connect(_on_normal)
	_hard_button.pressed.connect(_on_hard)
	SaveManager.currencies_changed.connect(_on_currencies_changed)
	SaveManager.campaign_changed.connect(_on_campaign_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	_map_canvas.draw.connect(_on_map_draw)
	_apply_safe_area()

	_sector_label.text = "%s  %s" % [_map.sector_code, _map.sector_name]
	_build_nodes()
	_refresh_all()


# --- Build ------------------------------------------------------------------

func _build_nodes() -> void:
	for child in _map_canvas.get_children():
		child.queue_free()
	_node_buttons.clear()
	_map_canvas.custom_minimum_size = Vector2(0, _MAP_HEIGHT)

	for stage in _map.stages:
		if stage == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(_NODE_RADIUS * 2.2, _NODE_RADIUS * 2.2)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 26)
		btn.position = stage.map_position - btn.custom_minimum_size * 0.5
		btn.pressed.connect(_on_node_pressed.bind(stage.id))
		_map_canvas.add_child(btn)
		_node_buttons[stage.id] = btn


# --- Refresh ----------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_currencies()
	_refresh_nodes()
	_refresh_detail()
	_refresh_difficulty()
	_map_canvas.queue_redraw()


func _refresh_currencies() -> void:
	_energy_value.text = _format_int(SaveManager.get_rift_energy())
	_core_value.text = _format_int(SaveManager.get_rift_core())


func _refresh_nodes() -> void:
	var cleared := SaveManager.get_cleared_stage_ids()
	for stage in _map.stages:
		if stage == null or not _node_buttons.has(stage.id):
			continue
		var btn: Button = _node_buttons[stage.id]
		var unlocked := StageProgress.is_unlocked(_map, stage, cleared)
		var selected := stage.id == _selected_id
		var stars := SaveManager.get_stage_stars(stage.id)
		if not unlocked:
			btn.text = "🔒\n%s" % stage.label
			btn.modulate = Color(0.45, 0.45, 0.5, 1)
		else:
			btn.text = "%s\n%s" % [_star_text(stars), stage.label]
			btn.modulate = stage.planet_modulate
		btn.self_modulate = Palette.get_color("cyan", Color(0, 0.84, 1)) if selected else Color.WHITE


func _refresh_detail() -> void:
	var stage := _map.find_by_id(_selected_id)
	if stage == null:
		_detail_title.text = "NO MISSION"
		_launch_button.disabled = true
		return

	var unlocked := StageProgress.is_unlocked(_map, stage, SaveManager.get_cleared_stage_ids())
	var player_power := _player_power()
	_detail_title.text = "SECTOR %s  ·  %s  %s" % [_map.sector_code, stage.label, stage.title]
	_detail_enemy.text = stage.enemy_label
	_detail_objective.text = stage.objective
	_power_recommended.text = "REC  %s" % _format_int(stage.recommended_power)
	_power_yours.text = "YOU  %s" % _format_int(player_power)
	if player_power >= stage.recommended_power:
		_power_yours.add_theme_color_override("font_color", Palette.get_color("green", Color(0.21, 0.89, 0.44)))
	else:
		_power_yours.add_theme_color_override("font_color", Palette.get_color("orange", Color(1, 0.48, 0.1)))

	_rewards_label.text = "REWARDS  Energy %s  ·  Core %d" % [
		_format_int(stage.reward_rift_energy), stage.reward_rift_core]
	var cleared := SaveManager.is_stage_cleared(stage.id)
	if cleared:
		_first_clear_label.text = "FIRST CLEAR  claimed"
		_first_clear_label.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))
	else:
		_first_clear_label.text = "FIRST CLEAR  Core +%d" % stage.first_clear_rift_core
		_first_clear_label.add_theme_color_override("font_color", Palette.get_color("purple", Color(0.55, 0.26, 1)))

	_stars_label.text = "STARS  %s" % _star_text(SaveManager.get_stage_stars(stage.id))

	var can_launch := SaveManager.can_launch_stage(_map, stage.id)
	_launch_button.disabled = not can_launch
	if not unlocked:
		_lock_label.visible = true
		_lock_label.text = "LOCKED  ·  Clear the previous stage"
		_launch_button.text = "LOCKED"
	elif SaveManager.get_campaign_difficulty() != SaveManager.DIFFICULTY_NORMAL:
		_lock_label.visible = true
		_lock_label.text = "HARD difficulty is locked in this prototype"
		_launch_button.text = "LOCKED"
	else:
		_lock_label.visible = false
		_launch_button.text = "LAUNCH"


func _refresh_difficulty() -> void:
	var normal := SaveManager.get_campaign_difficulty() == SaveManager.DIFFICULTY_NORMAL
	_normal_button.disabled = false
	_hard_button.disabled = false
	_normal_button.modulate = Palette.get_color("cyan", Color(0, 0.84, 1)) if normal else Color.WHITE
	_hard_button.modulate = Color(0.55, 0.45, 0.7, 1)
	_hard_button.text = "HARD  🔒"
	_normal_button.text = "NORMAL"


# --- Map draw ---------------------------------------------------------------

func _on_map_draw() -> void:
	if _map == null:
		return
	var cleared := SaveManager.get_cleared_stage_ids()
	var stages := _map.stages
	for i in range(stages.size() - 1):
		var a: StageNodeData = stages[i]
		var b: StageNodeData = stages[i + 1]
		if a == null or b == null:
			continue
		var unlocked_b := StageProgress.is_unlocked(_map, b, cleared)
		var color := Palette.get_color("purple", Color(0.55, 0.26, 1)) if unlocked_b else Palette.get_color("muted", Color(0.46, 0.57, 0.71))
		color.a = 0.85 if unlocked_b else 0.5
		if unlocked_b:
			_map_canvas.draw_line(a.map_position, b.map_position, color, 6.0)
		else:
			# Dashed path for locked ahead segments.
			var delta := b.map_position - a.map_position
			var len := delta.length()
			if len > 1.0:
				var dir := delta / len
				var t := 0.0
				while t < len:
					var p0 := a.map_position + dir * t
					var p1 := a.map_position + dir * minf(t + 18.0, len)
					_map_canvas.draw_line(p0, p1, color, 3.0)
					t += 34.0

	# Selected highlight ring.
	var selected := _map.find_by_id(_selected_id)
	if selected != null:
		var ring := Palette.get_color("cyan", Color(0, 0.84, 1))
		_map_canvas.draw_arc(selected.map_position, _NODE_RADIUS + 14.0, 0.0, TAU, 48, ring, 4.0)


# --- Interactions -----------------------------------------------------------

func _on_node_pressed(stage_id: String) -> void:
	_selected_id = stage_id
	SaveManager.select_stage(stage_id)
	_click()
	_refresh_all()


func _on_launch() -> void:
	var stage := _map.find_by_id(_selected_id)
	if stage == null or not SaveManager.can_launch_stage(_map, stage.id):
		_show_feedback("Stage unavailable", true)
		AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_LOW)
		return
	_click()
	SaveManager.select_stage(stage.id)
	SceneRouter.go_to(SceneRouter.SCREEN_RUN, {
		"sector": stage.index,
		"stage_id": stage.id,
	})


func _on_normal() -> void:
	SaveManager.set_campaign_difficulty(SaveManager.DIFFICULTY_NORMAL)
	_click()
	_refresh_all()


func _on_hard() -> void:
	# HARD remains locked — selecting it only shows the locked launch state.
	SaveManager.set_campaign_difficulty(SaveManager.DIFFICULTY_HARD)
	_click()
	_show_feedback("HARD is locked in this prototype", true)
	_refresh_all()


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _on_hangar() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR)


func _on_currencies_changed(_e: int, _c: int) -> void:
	_refresh_currencies()


func _on_campaign_changed(stage_id: String) -> void:
	if stage_id != "":
		_selected_id = stage_id
	_refresh_all()


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.light()


func _show_feedback(text: String, is_error: bool) -> void:
	_feedback_label.text = text
	_feedback_label.add_theme_color_override(
		"font_color",
		Palette.get_color("danger", Color(1, 0.23, 0.31)) if is_error else Palette.get_color("green", Color(0.21, 0.89, 0.44)))
	_feedback_label.modulate.a = 1.0
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.3)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.4)


func _player_power() -> int:
	var catalog: ShipCatalogData = load("res://resources/ships/ship_catalog_default.tres")
	if catalog == null:
		return 0
	var ship := catalog.find_by_id(SaveManager.get_selected_ship_id())
	if ship == null:
		return 0
	return StageProgress.player_power_from(ship, SaveManager.get_upgrade_levels(ship.id))


func _star_text(stars: int) -> String:
	var out := ""
	for i in 3:
		out += "★" if i < stars else "☆"
	return out


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


func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	_safe.add_theme_constant_override("margin_bottom", int(_BASE_PADDING + (full.y - (safe.position.y + safe.size.y))))
