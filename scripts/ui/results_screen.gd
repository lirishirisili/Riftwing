class_name ResultsScreen
extends Control
## Victory / failure run-results screen.
##
## Celebrates first (a title beat), then presents the run's statistics, the
## rewards it earned, and sector progression, with three navigation actions:
## Next Sector, Upgrade Ship, and Home (docs/03_SCREEN_SPEC.md,
## prompts/07_results_screen.md). All text is real Godot controls and all
## branding reads RIFTWING.
##
## Rewards are computed by the pure RewardCalculator from the run's RunStats and
## banked by SaveManager exactly once per run id, so re-opening this screen for
## the same run shows the earned totals without granting them again.

const _RULES_PATH := "res://resources/progression/reward_rules_default.tres"
const _BASE_PADDING := 48.0

@onready var _safe: MarginContainer = $Safe
@onready var _title: Label = $Safe/Root/Header/Title
@onready var _subtitle: Label = $Safe/Root/Header/Subtitle
@onready var _score_value: Label = $Safe/Root/ScorePanel/ScoreBox/ScoreValue
@onready var _stats_box: VBoxContainer = $Safe/Root/StatsPanel/StatsBox
@onready var _reward_box: HBoxContainer = $Safe/Root/RewardPanel/RewardBox
@onready var _progress_label: Label = $Safe/Root/ProgressPanel/ProgressLabel
@onready var _next_button: Button = %NextSector
@onready var _upgrade_button: Button = %UpgradeShip
@onready var _home_button: Button = %Home

var _stats: RunStats
var _rules: RewardRulesData
var _rewards: RunRewards
## True when this open actually banked rewards (first time for this run id).
var _granted_now: bool = false


## Accepts the finished run's data from the router. Called before _ready, so we
## stash it and process in _ready once nodes exist.
func receive_payload(payload: Dictionary) -> void:
	if payload.has("stats") and payload["stats"] is RunStats:
		_stats = payload["stats"]


func _ready() -> void:
	_rules = load(_RULES_PATH)
	if _rules == null:
		_rules = RewardRulesData.new()
	if _stats == null:
		# Standalone open (e.g. opening the scene directly): show a zeroed defeat
		# so the screen is always renderable and testable.
		_stats = RunStats.new()
		_stats.run_id = "standalone_%d" % Time.get_ticks_msec()

	_stats.finalize_score(_rules)
	_rewards = RewardCalculator.calculate(_stats, _rules)

	# Grant exactly once: SaveManager dedupes by run id and returns false if this
	# run was already banked (so re-entry never double-grants).
	_granted_now = SaveManager.grant_run_rewards(_stats.run_id, _rewards, _stats)

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_populate()
	_wire_buttons()
	_play_intro()


func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	_safe.add_theme_constant_override("margin_bottom", int(_BASE_PADDING + (full.y - (safe.position.y + safe.size.y))))


func _populate() -> void:
	if _stats.victory:
		_title.text = "SECTOR CLEARED"
		_title.add_theme_color_override("font_color", Palette.get_color("cyan", Color(0, 0.84, 1)))
		_subtitle.text = "RIFTWING  ·  mission complete"
		_subtitle.add_theme_color_override("font_color", Palette.get_color("gold", Color(1, 0.69, 0)))
	else:
		_title.text = "RIFTWING DOWN"
		_title.add_theme_color_override("font_color", Palette.get_color("danger", Color(1, 0.23, 0.31)))
		_subtitle.text = "Regroup and dive again"
		_subtitle.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))

	_score_value.text = _format_int(_stats.score)

	_set_stat_rows([
		["Enemies Destroyed", str(_stats.enemies_destroyed)],
		["Best Combo", "x%d" % _stats.best_combo],
		["Survival Time", _format_time(_stats.survival_seconds)],
		["Rift Energy Collected", str(_stats.rift_energy_collected)],
	])

	_set_reward_chips()

	var claimed := "" if _granted_now else "  (already claimed)"
	_progress_label.text = "SECTOR %d %s%s\nBest Score  %s" % [
		_stats.sector,
		"CLEARED" if _stats.victory else "FAILED",
		claimed,
		_format_int(SaveManager.get_best_score()),
	]


## Rebuilds the stat rows as real Label pairs inside the stats container.
func _set_stat_rows(rows: Array) -> void:
	for child in _stats_box.get_children():
		child.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = String(row[0])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))
		name_label.add_theme_font_size_override("font_size", 34)
		var value_label := Label.new()
		value_label.text = String(row[1])
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 38)
		line.add_child(name_label)
		line.add_child(value_label)
		_stats_box.add_child(line)


## Rebuilds the reward chips (Rift Energy always, Rift Core only when > 0).
func _set_reward_chips() -> void:
	for child in _reward_box.get_children():
		child.queue_free()
	_add_reward_chip("RIFT ENERGY", "+%s" % _format_int(_rewards.rift_energy), "cyan")
	if _rewards.rift_core > 0:
		_add_reward_chip("RIFT CORE", "+%d" % _rewards.rift_core, "purple")


func _add_reward_chip(label_text: String, amount_text: String, color_token: String) -> void:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var amount := Label.new()
	amount.text = amount_text
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", 48)
	amount.add_theme_color_override("font_color", Palette.get_color(color_token, Color.WHITE))
	var name_label := Label.new()
	name_label.text = label_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))
	box.add_child(amount)
	box.add_child(name_label)
	chip.add_child(box)
	_reward_box.add_child(chip)


func _wire_buttons() -> void:
	# Next Sector advances the campaign pointer and starts another run.
	# Upgrade Ship opens the hangar; Home returns to the main menu.
	_next_button.pressed.connect(_on_next_sector)
	_upgrade_button.pressed.connect(_on_upgrade_ship)
	_home_button.pressed.connect(_on_home)


func _on_next_sector() -> void:
	_click_feedback()
	# Return to the galaxy map, preferring the next stage after a clear.
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
	SceneRouter.go_to(SceneRouter.SCREEN_HANGAR)


func _on_home() -> void:
	_click_feedback()
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _click_feedback() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.light()


## Celebration beat: the title pops in and the panels rise, before the numbers
## settle (docs/03: celebrate before presenting numbers).
func _play_intro() -> void:
	var header: Control = $Safe/Root/Header
	header.scale = Vector2(0.8, 0.8)
	header.pivot_offset = header.size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(header, "scale", Vector2.ONE, 0.35)

	AudioManager.play_sfx(
		"victory_fanfare" if _stats.victory else "run_failed",
		Vector2.ZERO,
		AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.medium()


func _format_int(value: int) -> String:
	# Thousands separators for readable scores.
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
