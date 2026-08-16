class_name DailyScreen
extends Control
## Daily Challenge hub — deterministic run from the local date (no backend).
##
## Shows today's stage + modifier + one-time Rift Core reward, whether it has been
## claimed today, and launches the run with the daily payload. The reward is banked
## once per local date by SaveManager.grant_run_rewards.

const _GLOW := preload("res://scenes/ui/chrome/glow_cta_button.tscn")

@onready var _shell: MetaScreenShell = %Shell

var _challenge: Dictionary = {}
var _status_label: Label
var _launch_button: GlowCtaButton
var _header_back: HeaderBackButton


func _ready() -> void:
	_challenge = DailyChallenge.build()
	var body := _shell.get_body()

	_header_back = HeaderBackButton.new()
	_header_back.pressed.connect(_on_back)
	_shell.set_trailing(_header_back)

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(top_spacer)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NeonPanel"
	body.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := Label.new()
	title.text = "DAILY CHALLENGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	col.add_child(title)

	var date_label := Label.new()
	date_label.text = String(_challenge.get("date_key", ""))
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_label.add_theme_font_size_override("font_size", 24)
	date_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1, 1))
	col.add_child(date_label)

	col.add_child(_info_row("SECTOR STAGE", String(_challenge.get("stage_id", "1-1"))))
	col.add_child(_info_row("MODIFIER", String(_challenge.get("modifier_label", ""))))
	col.add_child(_info_row("REWARD", "%d Rift Core (once/day)" % int(_challenge.get("reward_core", 0))))

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 26)
	col.add_child(_status_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(bottom_spacer)

	_launch_button = _GLOW.instantiate() as GlowCtaButton
	body.add_child(_launch_button)
	_launch_button.pressed.connect(_on_launch)

	_refresh_status()


func _info_row(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 24)
	k.add_theme_color_override("font_color", Color(0.55, 0.68, 0.85, 1))
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 26)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row


func _refresh_status() -> void:
	var claimed := SaveManager.is_daily_completed(String(_challenge.get("date_key", "")))
	if claimed:
		_status_label.text = "COMPLETED TODAY  ·  reward already claimed"
		_status_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6, 1))
		_launch_button.configure("PLAY AGAIN", "NO REWARD", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE)
	else:
		_status_label.text = "REWARD AVAILABLE  ·  clear the run to claim"
		_status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
		_launch_button.configure("LAUNCH DAILY", "EARN RIFT CORE", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN)


func _on_launch() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	# Only offer the reward when it is still unclaimed today.
	var unclaimed := not SaveManager.is_daily_completed(String(_challenge.get("date_key", "")))
	SceneRouter.go_to(SceneRouter.SCREEN_RUN, {
		"sector": 1,
		"stage_id": String(_challenge.get("stage_id", "1-1")),
		"difficulty": String(_challenge.get("difficulty", "normal")),
		"daily": true,
		"daily_date": String(_challenge.get("date_key", "")),
		"daily_reward_core": int(_challenge.get("reward_core", 0)) if unclaimed else 0,
	})


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)
