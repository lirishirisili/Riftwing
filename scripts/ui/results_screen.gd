class_name ResultsScreen
extends Control
## Production victory / defeat results (prompts/21_results_screen_production.md).
##
## Celebrates the outcome, shows run stats + rewards, and offers Next Sector /
## Upgrade / Replay / Home. Rewards go through RewardCalculator +
## SaveManager.grant_run_rewards (deduped by run id). Branding: RIFTSTRIKE only.

const _RULES_PATH := "res://resources/progression/reward_rules_default.tres"
const _CATALOG_PATH := "res://resources/ships/ship_catalog_default.tres"
const _SCROLL_SPEED := 10.0
const _ICON_ENERGY := "res://assets/icons/icon_energy.svg"
const _ICON_CORE := "res://assets/icons/icon_crystal.svg"
const _ICON_BOSS := "res://assets/icons/icon_boss.svg"
const _ICON_MISSILE := "res://assets/icons/icon_missile.svg"

@onready var _shell: MetaScreenShell = %Shell
@onready var _parallax: ParallaxBackground = $Background
@onready var _nebula: Sprite2D = %NebulaSprite
@onready var _safe: MarginContainer = $Safe
@onready var _title: Label = $Safe/Root/Header/TitleRow/Title
@onready var _subtitle: Label = $Safe/Root/Header/Subtitle
@onready var _left_wings: HBoxContainer = %LeftWings
@onready var _right_wings: HBoxContainer = %RightWings
@onready var _hero_ship: TextureRect = %HeroShip
@onready var _engine_glow: TextureRect = %EngineGlow
@onready var _emblem_panel: PanelContainer = %EmblemPanel
@onready var _emblem_title: Label = %EmblemTitle
@onready var _emblem_sub: Label = %EmblemSub
@onready var _score_value: Label = $Safe/Root/ScorePanel/ScoreBox/ScoreValue
@onready var _best_badge: PanelContainer = %BestBadge
@onready var _stats_box: VBoxContainer = %StatsBox
@onready var _reward_box: HBoxContainer = %RewardBox
@onready var _progress_label: Label = $Safe/Root/ProgressPanel/ProgressLabel
@onready var _next_button: GlowCtaButton = %NextSector
@onready var _upgrade_button: GlowCtaButton = %UpgradeShip
@onready var _replay_button: GlowCtaButton = %ReplayButton
@onready var _home_button: GlowCtaButton = %Home
@onready var _confetti: CPUParticles2D = %Confetti

var _stats: RunStats
var _rules: RewardRulesData
var _rewards: RunRewards
var _granted_now: bool = false
var _hero_time := 0.0
var _was_new_best := false


func receive_payload(payload: Dictionary) -> void:
	if payload.has("stats") and payload["stats"] is RunStats:
		_stats = payload["stats"]


## Resolves the map node for the run's stage, or null when played outside the map.
func _resolve_stage() -> StageNodeData:
	if _stats == null or _stats.stage_id == "":
		return null
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres") as StageMapData
	if map == null:
		return null
	return map.find_by_id(_stats.stage_id)


func _ready() -> void:
	_rules = load(_RULES_PATH)
	if _rules == null:
		_rules = RewardRulesData.new()
	if _stats == null:
		_stats = RunStats.new()
		_stats.run_id = "standalone_%d" % Time.get_ticks_msec()

	_stats.finalize_score(_rules)
	var stage := _resolve_stage()
	# First clear is decided BEFORE granting so the bonus is only offered once.
	var is_first_clear := _stats.victory and stage != null and not SaveManager.is_stage_cleared(_stats.stage_id, _stats.difficulty)
	_rewards = RewardCalculator.calculate(_stats, _rules, stage, is_first_clear)
	var best_before := SaveManager.get_best_score()
	_was_new_best = _stats.score > best_before

	# Grant exactly once: SaveManager dedupes by run id.
	_granted_now = SaveManager.grant_run_rewards(_stats.run_id, _rewards, _stats)

	_ensure_scroll_layout()
	_mount_meta_shell()
	get_viewport().size_changed.connect(_on_viewport_changed)
	_on_viewport_changed()
	_populate()
	_wire_buttons()
	_play_intro()
	GameFeel.debug_markers_enabled = false
	AudioManager.stop_music()
	set_process(true)


func _mount_meta_shell() -> void:
	for path in ["Base", "Background", "VignetteTop", "VignetteBottom"]:
		var n := get_node_or_null(path)
		if n != null:
			n.visible = false
	if _shell == null or _safe == null:
		return
	var column := _safe.get_node_or_null("Column") as VBoxContainer
	if column == null:
		return
	_safe.remove_child(column)
	_shell.get_body().add_child(column)
	_adopt_owner(column)
	_safe.visible = false
	_shell.refresh_currencies()


func _adopt_owner(node: Node) -> void:
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


## Sticky CTAs + scrollable summary so safe-area phones never clip buttons.
func _ensure_scroll_layout() -> void:
	if _safe.get_node_or_null("Column") != null:
		return
	var root := _safe.get_node_or_null("Root") as VBoxContainer
	if root == null:
		return
	var buttons := root.get_node_or_null("Buttons") as VBoxContainer
	if buttons == null:
		return
	root.remove_child(buttons)
	_safe.remove_child(root)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_safe.add_child(column)
	column.add_child(scroll)
	scroll.add_child(root)
	column.add_child(buttons)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END


func _process(delta: float) -> void:
	if _parallax != null and _parallax.visible:
		_parallax.scroll_offset.y += delta * _SCROLL_SPEED
	_hero_time += delta
	if _hero_ship != null:
		var pulse := 1.0 + sin(_hero_time * 1.4) * 0.02
		_hero_ship.scale = Vector2(pulse, pulse)
		_hero_ship.rotation = sin(_hero_time * 0.5) * 0.025
	if _engine_glow != null:
		_engine_glow.modulate.a = 0.5 + sin(_hero_time * 2.8) * 0.22
	if _left_wings != null and _right_wings != null:
		var wing_a := 0.72 + absf(sin(_hero_time * 2.2)) * 0.28
		_left_wings.modulate.a = wing_a
		_right_wings.modulate.a = wing_a
	if _best_badge != null and _best_badge.visible:
		var glow := 0.9 + absf(sin(_hero_time * 2.0)) * 0.1
		_best_badge.modulate = Color(glow, glow * 0.95, 0.85, 1.0)


func _on_viewport_changed() -> void:
	call_deferred("_recenter_hero")
	call_deferred("_recenter_confetti")


func _recenter_hero() -> void:
	if _hero_ship != null:
		_hero_ship.pivot_offset = _hero_ship.size * 0.5
	if _engine_glow != null:
		_engine_glow.pivot_offset = _engine_glow.size * 0.5


func _recenter_confetti() -> void:
	if _confetti == null:
		return
	var size := get_viewport_rect().size
	_confetti.position = Vector2(size.x * 0.5, size.y * 0.08)
	_confetti.emission_rect_extents = Vector2(size.x * 0.42, 20.0)


func _populate() -> void:
	_apply_hero_ship()
	if _stats.victory:
		_title.text = "VICTORY"
		_title.add_theme_color_override("font_color", Color(0.96, 0.98, 1, 1))
		_title.add_theme_color_override("font_shadow_color", Color(0, 0.8, 1, 0.7))
		_subtitle.text = "SECTOR CLEARED"
		_subtitle.add_theme_color_override("font_color", Palette.get_color("gold", Color(1, 0.69, 0)))
		_set_wing_tint(Palette.get_color("cyan", Color(0, 0.84, 1)))
		if _nebula != null:
			_nebula.modulate = Color(0.55, 0.45, 1.0, 0.55)
		_next_button.configure("NEXT SECTOR  >>", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 108.0)
		_next_button.chrome_modulate = Color(1.05, 0.95, 0.75, 1)
		_upgrade_button.configure("UPGRADE SHIP", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.NONE, 108.0)
		_replay_button.configure("REPLAY", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 88.0)
	else:
		_title.text = "DEFEAT"
		_title.add_theme_color_override("font_color", Palette.get_color("danger", Color(1, 0.23, 0.31)))
		_title.add_theme_color_override("font_shadow_color", Color(1, 0.15, 0.25, 0.45))
		_subtitle.text = "%s  ·  regroup" % Brand.DEFEAT_LINE
		_subtitle.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))
		_set_wing_tint(Palette.get_color("danger", Color(1, 0.23, 0.31)))
		if _nebula != null:
			_nebula.modulate = Color(0.55, 0.2, 0.35, 0.45)
		_next_button.configure("SECTOR MAP", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 108.0)
		_next_button.chrome_modulate = Color.WHITE
		_upgrade_button.configure("UPGRADE SHIP", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 108.0)
		_replay_button.configure("REPLAY", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 88.0)
	_home_button.configure("HOME", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 88.0)

	_score_value.text = _format_int(_stats.score)
	_best_badge.visible = _was_new_best or (_stats.score > 0 and _stats.score >= SaveManager.get_best_score())
	_populate_emblem()

	var rows: Array = [
		["Enemies Destroyed", str(_stats.enemies_destroyed), _ICON_BOSS],
		["Best Combo", "x%d" % _stats.best_combo, _ICON_MISSILE],
		["Survival Time", _format_time(_stats.survival_seconds), _ICON_ENERGY],
		["Rift Energy", str(_stats.rift_energy_collected), _ICON_ENERGY],
	]
	if _stats.stage_id != "":
		rows.append(["Stage", _stats.stage_id, _ICON_BOSS])
	_set_stat_rows(rows)
	_set_reward_chips()

	var claimed := "" if _granted_now else "  ·  already claimed"
	var stars_txt := ""
	if _stats.stage_id != "":
		var map: StageMapData = load("res://resources/stages/nova_sector_map.tres") as StageMapData
		var stage: StageNodeData = map.find_by_id(_stats.stage_id) if map != null else null
		if _stats.victory:
			var stars := SaveManager.get_stage_stars(_stats.stage_id)
			stars_txt = "\nSTARS  %s" % _star_text(stars)
			if stage != null:
				stars_txt += "\n" + "\n".join(StageProgress.star_objective_lines(stage))
		else:
			stars_txt = "\nAlmost there — upgrade in Hangar, then retry."
			if stage != null:
				stars_txt += "\n" + "\n".join(StageProgress.star_objective_lines(stage))
	_progress_label.text = "SECTOR %d  %s%s\nBest Score  %s%s" % [
		_stats.sector,
		"CLEARED" if _stats.victory else "FAILED",
		claimed,
		_format_int(SaveManager.get_best_score()),
		stars_txt,
	]


func _set_wing_tint(tint: Color) -> void:
	for wing in [_left_wings, _right_wings]:
		if wing == null:
			continue
		var i := 0
		for child in wing.get_children():
			if child is ColorRect:
				var bar := child as ColorRect
				var a := 0.5 + float(i) * 0.2
				bar.color = Color(tint.r, tint.g, tint.b, clampf(a, 0.45, 1.0))
				i += 1


func _apply_hero_ship() -> void:
	var catalog: ShipCatalogData = load(_CATALOG_PATH) as ShipCatalogData
	if catalog == null:
		return
	var ship := catalog.find_by_id(SaveManager.get_selected_ship_id())
	if ship == null:
		return
	if ship.hero_texture != null:
		_hero_ship.texture = ship.hero_texture
	elif ship.portrait != null:
		_hero_ship.texture = ship.portrait
	_hero_ship.modulate = ship.accent_modulate


func _populate_emblem() -> void:
	if _stats.victory:
		if _stats.best_combo >= 20 or _stats.score >= 5000:
			_emblem_title.text = "LEGENDARY RUN"
			_emblem_sub.text = "Peak performance"
		elif _stats.best_combo >= 8:
			_emblem_title.text = "ACE PILOT"
			_emblem_sub.text = "Strong clear"
		else:
			_emblem_title.text = "MISSION COMPLETE"
			_emblem_sub.text = "Sector secured"
		_emblem_panel.modulate = Color(1, 1, 1, 1)
	else:
		_emblem_title.text = "RIFT BREACH"
		_emblem_sub.text = "Try again"
		_emblem_panel.modulate = Color(0.85, 0.75, 0.8, 1)


func _set_stat_rows(rows: Array) -> void:
	for child in _stats_box.get_children():
		child.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_constant_override("separation", 12)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(String(row[2])) as Texture2D
		icon.modulate = Palette.get_color("cyan", Color(0, 0.84, 1))
		var name_label := Label.new()
		name_label.text = String(row[0]).to_upper()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))
		name_label.add_theme_font_size_override("font_size", 26)
		var value_label := Label.new()
		value_label.text = String(row[1])
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 30)
		value_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1, 1))
		line.add_child(icon)
		line.add_child(name_label)
		line.add_child(value_label)
		_stats_box.add_child(line)


func _set_reward_chips() -> void:
	for child in _reward_box.get_children():
		child.queue_free()
	_add_reward_chip("RIFT ENERGY", "+%s" % _format_int(_rewards.rift_energy), "cyan", _ICON_ENERGY)
	if _rewards.rift_core > 0:
		_add_reward_chip("RIFT CORE", "+%d" % _rewards.rift_core, "purple", _ICON_CORE)


func _add_reward_chip(label_text: String, amount_text: String, color_token: String, icon_path: String) -> void:
	var accent := Palette.get_color(color_token, Color.WHITE)
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size = Vector2(140, 148)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.07, 0.14, 0.95)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 12
	style.content_margin_top = 14
	style.content_margin_right = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	style.shadow_size = 12
	chip.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(icon_path) as Texture2D
	icon.modulate = accent
	var amount := Label.new()
	amount.text = amount_text
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", 40)
	amount.add_theme_color_override("font_color", accent)
	amount.add_theme_color_override("font_shadow_color", Color(accent.r, accent.g, accent.b, 0.45))
	amount.add_theme_constant_override("shadow_outline_size", 6)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))
	box.add_child(icon)
	box.add_child(amount)
	box.add_child(name_label)
	chip.add_child(box)
	_reward_box.add_child(chip)


func _wire_buttons() -> void:
	_next_button.pressed.connect(_on_next_sector)
	_upgrade_button.pressed.connect(_on_upgrade_ship)
	_replay_button.pressed.connect(_on_replay)
	_home_button.pressed.connect(_on_home)


func _on_next_sector() -> void:
	_click_feedback()
	var payload := {}
	if _stats.stage_id != "":
		var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
		if map != null:
			var nxt := map.next_after(_stats.stage_id)
			if nxt != null:
				payload["stage_id"] = nxt.id
			else:
				payload["stage_id"] = _stats.stage_id
	SceneRouter.go_to(SceneRouter.SCREEN_STAGE_MAP, payload)


func _on_upgrade_ship() -> void:
	_click_feedback()
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR, {
		"return_to": SceneRouter.SCREEN_RESULTS,
		"return_payload": {"stats": _stats},
	})


func _on_replay() -> void:
	_click_feedback()
	var payload := {
		"sector": _stats.sector,
		"stage_id": _stats.stage_id,
		"difficulty": _stats.difficulty,
	}
	SceneRouter.go_to(SceneRouter.SCREEN_RUN, payload)


func handle_system_back() -> bool:
	_on_home()
	return true


func _on_home() -> void:
	_click_feedback()
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _click_feedback() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null and GameFeel.haptics_enabled:
		haptics.light()


func _play_intro() -> void:
	var header: Control = _title.get_parent().get_parent() as Control
	if header == null:
		return
	header.scale = Vector2(0.82, 0.82)
	header.pivot_offset = header.size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(header, "scale", Vector2.ONE, 0.38)
	if _emblem_panel != null:
		_emblem_panel.modulate.a = 0.0
		tween.parallel().tween_property(_emblem_panel, "modulate:a", 1.0, 0.4)

	if _stats.victory and _confetti != null:
		_recenter_confetti()
		_confetti.restart()
		_confetti.emitting = true

	AudioManager.play_sfx(
		"victory_fanfare" if _stats.victory else "run_failed",
		Vector2.ZERO,
		AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null and GameFeel.haptics_enabled:
		haptics.medium()


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


func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%d:%02d" % [total / 60, total % 60]
