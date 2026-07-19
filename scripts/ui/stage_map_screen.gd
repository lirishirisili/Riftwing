class_name StageMapScreen
extends Control
## Production galaxy map / stage select (prompts/19_galaxy_map_production.md).
##
## Data-driven mission nodes from StageMapData with glowing paths, clear
## completed / current / unlocked / locked states, mission detail panel, and
## Launch into a real run. Save / unlock / HARD restrictions unchanged.
## Branding reads RIFTWING only.

const _MAP_PATH := "res://resources/stages/nova_sector_map.tres"
const _TEX_NODE_ACTIVE: Texture2D = preload("res://assets/ui/chrome/map_node_active.svg")
const _TEX_NODE_LOCKED: Texture2D = preload("res://assets/ui/chrome/map_node_locked.svg")
const _NODE_RADIUS := 46.0
const _MAP_HEIGHT := 1180.0
const _ICON_SIZE := 72

@onready var _shell: MetaScreenShell = %Shell
@onready var _legacy_safe: MarginContainer = %Safe
@onready var _sector_label: Label = %SectorLabel
@onready var _progress_label: Label = %ProgressLabel
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
@onready var _launch_button: GlowCtaButton = %LaunchButton
@onready var _normal_button: GlowCtaButton = %NormalButton
@onready var _hard_button: GlowCtaButton = %HardButton
@onready var _back_button: GlowCtaButton = %BackButton
@onready var _hangar_button: GlowCtaButton = %HangarButton
@onready var _feedback_label: Label = %FeedbackLabel

var _map: StageMapData
var _selected_id: String = ""
var _node_buttons: Dictionary = {} # stage_id -> Button
var _feedback_tween: Tween
var _pulse_time := 0.0


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

	_mount_meta_shell()
	_back_button.pressed.connect(_on_back)
	_hangar_button.pressed.connect(_on_hangar)
	_launch_button.pressed.connect(_on_launch)
	_normal_button.pressed.connect(_on_normal)
	_hard_button.pressed.connect(_on_hard)
	SaveManager.campaign_changed.connect(_on_campaign_changed)
	_map_canvas.draw.connect(_on_map_draw)

	_sector_label.text = "%s  %s" % [_map.sector_code, _map.sector_name]
	_build_nodes()
	_refresh_all()
	GameFeel.debug_markers_enabled = false
	AudioManager.play_music("menu")
	set_process(true)


func _mount_meta_shell() -> void:
	# Prefer shared MetaScreenShell chrome; keep map body under %Body.
	for path in ["Base", "Background", "VignetteTop", "VignetteBottom"]:
		var n := get_node_or_null(path)
		if n != null:
			n.visible = false
	var root := _legacy_safe.get_node_or_null("Root") as VBoxContainer
	if root == null or _shell == null:
		return
	var body := _shell.get_body()
	var to_move: Array[Node] = []
	for child in root.get_children():
		if child.name != "TopBar":
			to_move.append(child)
	for child in to_move:
		root.remove_child(child)
		body.add_child(child)
		_adopt_owner(child)
	_legacy_safe.visible = false
	if _back_button.get_parent() != null:
		_back_button.get_parent().remove_child(_back_button)
	_back_button.configure("BACK", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 68.0)
	_shell.set_trailing(_back_button)
	_adopt_owner(_back_button)
	_hangar_button.configure("HANGAR", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 96.0)
	_launch_button.configure("LAUNCH", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN)


func _adopt_owner(node: Node) -> void:
	## Keep screen % unique names on self; GlowCta internals stay owned by the instance.
	if node is GlowCtaButton:
		node.owner = self
		for child in node.get_children():
			_set_subtree_owner(child, node)
		return
	node.owner = self
	for child in node.get_children():
		_adopt_owner(child)


func _set_subtree_owner(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		_set_subtree_owner(child, new_owner)


func _process(delta: float) -> void:
	_pulse_time += delta
	_map_canvas.queue_redraw()


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
		btn.custom_minimum_size = Vector2(_NODE_RADIUS * 2.3, _NODE_RADIUS * 2.3)
		btn.focus_mode = Control.FOCUS_NONE
		btn.theme_type_variation = &"ButtonTertiary"
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_constant_override("icon_max_width", _ICON_SIZE)
		btn.expand_icon = true
		btn.clip_text = true
		btn.position = stage.map_position - btn.custom_minimum_size * 0.5
		btn.pressed.connect(_on_node_pressed.bind(stage.id))
		_map_canvas.add_child(btn)
		_node_buttons[stage.id] = btn


# --- Refresh ----------------------------------------------------------------

func _refresh_all() -> void:
	if _shell != null:
		_shell.refresh_currencies()
	_refresh_progress()
	_refresh_nodes()
	_refresh_detail()
	_refresh_difficulty()
	_map_canvas.queue_redraw()


func _refresh_progress() -> void:
	if _map == null:
		return
	var cleared := 0
	for stage in _map.stages:
		if stage != null and SaveManager.is_stage_cleared(stage.id):
			cleared += 1
	var total := _map.stages.size()
	_progress_label.text = "%d / %d  CLEARED" % [cleared, total]


func _refresh_nodes() -> void:
	var cleared_ids := SaveManager.get_cleared_stage_ids()
	var current_id := _next_current_stage_id(cleared_ids)
	for stage in _map.stages:
		if stage == null or not _node_buttons.has(stage.id):
			continue
		var btn: Button = _node_buttons[stage.id]
		var unlocked := StageProgress.is_unlocked(_map, stage, cleared_ids)
		var cleared := SaveManager.is_stage_cleared(stage.id)
		var selected := stage.id == _selected_id
		var is_current := stage.id == current_id
		var stars := SaveManager.get_stage_stars(stage.id)

		if not unlocked:
			btn.icon = _TEX_NODE_LOCKED
			btn.text = stage.label
			btn.modulate = Color(0.55, 0.58, 0.65, 1)
			btn.self_modulate = Color(0.85, 0.88, 0.95, 1)
		elif cleared:
			btn.icon = null
			btn.text = "%s\n%s" % [_star_text(stars), stage.label]
			btn.modulate = stage.planet_modulate
			btn.self_modulate = Palette.get_color("gold", Color(1, 0.85, 0.35)) if not selected else Palette.get_color("cyan", Color(0, 0.84, 1))
		else:
			var focus := selected or is_current
			btn.icon = _TEX_NODE_ACTIVE if focus else null
			# Keep label short when the active chrome icon is shown.
			btn.text = stage.label if focus else "%s\n%s" % [_star_text(stars), stage.label]
			btn.modulate = stage.planet_modulate
			if selected:
				btn.self_modulate = Palette.get_color("cyan", Color(0, 0.84, 1))
			elif is_current:
				btn.self_modulate = Color(0.85, 0.95, 1, 1)
			else:
				btn.self_modulate = Color.WHITE


func _refresh_detail() -> void:
	var stage := _map.find_by_id(_selected_id)
	if stage == null:
		_detail_title.text = "NO MISSION"
		_launch_button.disabled = true
		return

	var unlocked := StageProgress.is_unlocked(_map, stage, SaveManager.get_cleared_stage_ids())
	var player_power := _player_power()
	# Short readable title: "1-5  VOID OUTPOST"
	_detail_title.text = "%s  %s" % [stage.label, stage.title]
	_detail_enemy.text = "ENEMY  ·  %s" % stage.enemy_label
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

	var earned := SaveManager.get_stage_stars(stage.id)
	var obj := StageProgress.star_objective_lines(stage)
	_stars_label.text = "STARS  %s\n%s" % [_star_text(earned), "\n".join(obj)]

	var can_launch := SaveManager.can_launch_stage(_map, stage.id)
	_launch_button.set_enabled(can_launch)
	if not unlocked:
		_lock_label.visible = true
		_lock_label.text = "LOCKED  ·  Clear the previous stage"
		_launch_button.configure("LOCKED", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE)
		_launch_button.set_enabled(false)
	elif SaveManager.get_campaign_difficulty() != SaveManager.DIFFICULTY_NORMAL:
		_lock_label.visible = true
		_lock_label.text = "HARD difficulty is locked in this prototype"
		_launch_button.configure("LOCKED", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE)
		_launch_button.set_enabled(false)
	else:
		_lock_label.visible = false
		_launch_button.configure(
			"LAUNCH",
			"",
			GlowCtaButton.Variant.PRIMARY,
			GlowCtaButton.Pulse.CYAN if can_launch else GlowCtaButton.Pulse.NONE)
		_launch_button.set_enabled(can_launch)


func _refresh_difficulty() -> void:
	var normal := SaveManager.get_campaign_difficulty() == SaveManager.DIFFICULTY_NORMAL
	_normal_button.set_enabled(true)
	_hard_button.set_enabled(true)
	if normal:
		_normal_button.configure("NORMAL", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.CYAN, 72.0)
		_normal_button.chrome_modulate = Color(1, 1, 1, 1)
	else:
		_normal_button.configure("NORMAL", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 72.0)
		_normal_button.chrome_modulate = Color(0.7, 0.75, 0.85, 1)
	_hard_button.configure("HARD  🔒", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 72.0)
	_hard_button.chrome_modulate = Color(0.55, 0.45, 0.7, 1)


# --- Map draw ---------------------------------------------------------------

func _on_map_draw() -> void:
	if _map == null:
		return
	var cleared_ids := SaveManager.get_cleared_stage_ids()
	var current_id := _next_current_stage_id(cleared_ids)
	var stages := _map.stages

	# Soft route glow under the path.
	for i in range(stages.size() - 1):
		var a: StageNodeData = stages[i]
		var b: StageNodeData = stages[i + 1]
		if a == null or b == null:
			continue
		var a_cleared := SaveManager.is_stage_cleared(a.id)
		var unlocked_b := StageProgress.is_unlocked(_map, b, cleared_ids)
		if a_cleared and unlocked_b:
			var glow_c := Palette.get_color("cyan", Color(0, 0.84, 1))
			glow_c.a = 0.28
			_map_canvas.draw_line(a.map_position, b.map_position, glow_c, 16.0)
			var glow_p := Palette.get_color("purple", Color(0.55, 0.26, 1))
			glow_p.a = 0.16
			_map_canvas.draw_line(a.map_position, b.map_position, glow_p, 10.0)
		elif unlocked_b:
			var glow_u := Palette.get_color("purple", Color(0.55, 0.26, 1))
			glow_u.a = 0.22
			_map_canvas.draw_line(a.map_position, b.map_position, glow_u, 13.0)

	# Solid purple/cyan for cleared+unlocked; dashed muted for locked.
	for i in range(stages.size() - 1):
		var a2: StageNodeData = stages[i]
		var b2: StageNodeData = stages[i + 1]
		if a2 == null or b2 == null:
			continue
		var unlocked_b2 := StageProgress.is_unlocked(_map, b2, cleared_ids)
		var a_cleared2 := SaveManager.is_stage_cleared(a2.id)
		if unlocked_b2:
			if a_cleared2:
				var purple := Palette.get_color("purple", Color(0.55, 0.26, 1))
				purple.a = 0.95
				var cyan := Palette.get_color("cyan", Color(0, 0.84, 1))
				cyan.a = 0.95
				_draw_gradient_path(a2.map_position, b2.map_position, purple, cyan, 5.5)
			else:
				var color := Palette.get_color("purple", Color(0.55, 0.26, 1))
				color.a = 0.88
				_map_canvas.draw_line(a2.map_position, b2.map_position, color, 5.0)
		else:
			var muted := Palette.get_color("muted", Color(0.46, 0.57, 0.71))
			muted.a = 0.4
			_draw_dashed_path(a2.map_position, b2.map_position, muted, 3.0, 14.0, 18.0)

	# Per-node rings: completed / current / selected (stronger multi-ring pulse).
	for stage in stages:
		if stage == null:
			continue
		var unlocked := StageProgress.is_unlocked(_map, stage, cleared_ids)
		var cleared := SaveManager.is_stage_cleared(stage.id)
		var selected := stage.id == _selected_id
		var is_current := stage.id == current_id
		if cleared:
			var done := Palette.get_color("gold", Color(1, 0.69, 0))
			done.a = 0.6
			_map_canvas.draw_arc(stage.map_position, _NODE_RADIUS + 8.0, 0.0, TAU, 40, done, 3.0)
		if selected:
			_draw_pulse_rings(stage.map_position, Palette.get_color("cyan", Color(0, 0.84, 1)), 1.9, true)
		elif is_current and unlocked and not cleared:
			_draw_pulse_rings(stage.map_position, Palette.get_color("cyan", Color(0, 0.84, 1)), 2.4, false)


func _draw_pulse_rings(center: Vector2, base: Color, speed: float, selected: bool) -> void:
	var ring_count := 4 if selected else 3
	var base_r := _NODE_RADIUS + (14.0 if selected else 16.0)
	for i in ring_count:
		var phase := _pulse_time * speed - float(i) * 0.45
		var pulse := 0.45 + absf(sin(phase)) * 0.55
		var r := base_r + float(i) * 11.0 + sin(phase) * 3.5
		var c := base
		c.a = (0.9 - float(i) * 0.16) * pulse
		var width := 4.5 if (selected and i == 0) else (3.2 if i == 0 else 2.0)
		_map_canvas.draw_arc(center, r, 0.0, TAU, 56, c, width)
	if selected:
		var core := base
		core.a = 0.95
		_map_canvas.draw_arc(center, _NODE_RADIUS + 12.0, 0.0, TAU, 48, core, 5.0)


func _draw_gradient_path(from: Vector2, to: Vector2, c0: Color, c1: Color, width: float) -> void:
	var segments := 8
	var prev := from
	for s in range(1, segments + 1):
		var t := float(s) / float(segments)
		var p := from.lerp(to, t)
		var c := c0.lerp(c1, t)
		_map_canvas.draw_line(prev, p, c, width)
		prev = p


func _draw_dashed_path(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var delta := to - from
	var len := delta.length()
	if len <= 1.0:
		return
	var dir := delta / len
	var t := 0.0
	var stride := dash + gap
	while t < len:
		var p0 := from + dir * t
		var p1 := from + dir * minf(t + dash, len)
		_map_canvas.draw_line(p0, p1, color, width)
		t += stride


## First unlocked uncleared stage — the campaign "current" mission marker.
func _next_current_stage_id(cleared_ids: Array) -> String:
	if _map == null:
		return ""
	for stage in _map.stages:
		if stage == null:
			continue
		if StageProgress.is_unlocked(_map, stage, cleared_ids) and not SaveManager.is_stage_cleared(stage.id):
			return stage.id
	# All cleared — highlight the last stage.
	if _map.stages.size() > 0 and _map.stages[_map.stages.size() - 1] != null:
		return _map.stages[_map.stages.size() - 1].id
	return ""


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


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _on_hangar() -> void:
	_click()
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR)


func _on_campaign_changed(stage_id: String) -> void:
	if stage_id != "":
		_selected_id = stage_id
	_refresh_all()


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null and GameFeel.haptics_enabled:
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

