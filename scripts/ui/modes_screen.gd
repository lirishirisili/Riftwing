class_name ModesScreen
extends Control
## Extra modes hub: ENDLESS (escalating waves, a boss every lap) and BOSS RUSH
## (every boss the player has reached, back to back). Shows personal bests and
## unlock requirements; launches the run with a `mode` payload.

const _GLOW := preload("res://scenes/ui/chrome/glow_cta_button.tscn")
## Stage clears that unlock each mode.
const ENDLESS_UNLOCK_STAGE := "1-3"
const BOSS_RUSH_UNLOCK_STAGE := "1-10"

@onready var _shell: MetaScreenShell = %Shell

var _header_back: HeaderBackButton


func _ready() -> void:
	var body := _shell.get_body()
	_header_back = HeaderBackButton.new()
	_header_back.pressed.connect(_on_back)
	_shell.set_trailing(_header_back)

	var title := Label.new()
	title.text = "GAME MODES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	body.add_child(title)

	body.add_child(_mode_panel("endless", "ENDLESS",
		"Endless escalating waves. A boss arrives every 75 seconds, each one harder. How long can you last?",
		ENDLESS_UNLOCK_STAGE, Palette.get_color("cyan", Color(0.2, 0.9, 1.0))))
	body.add_child(_mode_panel("boss_rush", "BOSS RUSH",
		"Every boss you have reached, back to back, with a free upgrade between fights.",
		BOSS_RUSH_UNLOCK_STAGE, Palette.get_color("magenta", Color(1.0, 0.3, 0.9))))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	AudioManager.play_music("menu")


func _mode_panel(mode: String, title_text: String, blurb: String, unlock_stage: String, accent: Color) -> PanelContainer:
	var unlocked := SaveManager.is_stage_cleared(unlock_stage)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NeonPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", accent)
	col.add_child(t)

	var d := Label.new()
	d.text = blurb
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_font_size_override("font_size", 24)
	col.add_child(d)

	var best := SaveManager.get_mode_best(mode)
	var rec := Label.new()
	rec.add_theme_font_size_override("font_size", 24)
	rec.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	if int(best.get("runs", 0)) > 0:
		rec.text = "BEST  %s pts  ·  %s  ·  %d bosses" % [
			_fmt_int(int(best.get("best_score", 0))), _fmt_time(float(best.get("best_seconds", 0.0))),
			int(best.get("best_bosses", 0))]
	else:
		rec.text = "+1 RIFT CORE PER BOSS DESTROYED"
	col.add_child(rec)

	var btn := _GLOW.instantiate() as GlowCtaButton
	col.add_child(btn)
	if unlocked:
		btn.configure("LAUNCH %s" % title_text, "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 104.0)
		btn.pressed.connect(_on_launch.bind(mode))
	else:
		btn.configure("LOCKED", "CLEAR STAGE %s" % unlock_stage, GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 104.0)
		btn.set_enabled(false)
	return panel


func _on_launch(mode: String) -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_RUN, {
		"mode": mode,
		"difficulty": SaveManager.DIFFICULTY_NORMAL,
	})


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _fmt_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _fmt_int(value: int) -> String:
	var s := str(value)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
