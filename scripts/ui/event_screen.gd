class_name EventScreen
extends Control
## VOID INVASION event hub — a real, locally-timed challenge (no backend, no fake
## countdown). Shows the live window state, progress toward the goal, and a one-time
## reward claim. Progress accrues from enemies destroyed in runs during the window.

const _GLOW := preload("res://scenes/ui/chrome/glow_cta_button.tscn")
const _EVENT_PATH := "res://resources/events/void_invasion.tres"

@onready var _shell: MetaScreenShell = %Shell

var _event: EventData
var _header_back: HeaderBackButton
var _timer_label: Label
var _progress_bar: ProgressBar
var _progress_label: Label
var _status_label: Label
var _claim_button: GlowCtaButton
var _tick := 0.0


func _ready() -> void:
	_event = load(_EVENT_PATH) as EventData
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
	title.text = _event.display_name if _event != null else "EVENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.85, 0.5, 1, 1))
	col.add_child(title)

	var desc := Label.new()
	desc.text = _event.description if _event != null else ""
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 24)
	desc.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
	col.add_child(desc)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 30)
	col.add_child(_timer_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 34)
	_progress_bar.show_percentage = false
	col.add_child(_progress_bar)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 24)
	col.add_child(_progress_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 24)
	col.add_child(_status_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(bottom_spacer)

	_claim_button = _GLOW.instantiate() as GlowCtaButton
	body.add_child(_claim_button)
	_claim_button.pressed.connect(_on_claim)

	_refresh()
	set_process(true)


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh_timer()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _refresh() -> void:
	if _event == null:
		return
	_refresh_timer()
	var now := _now()
	var occ := _event.occurrence_id(now)
	var progress := SaveManager.get_event_progress(occ)
	var goal := maxi(1, _event.goal)
	_progress_bar.max_value = float(goal)
	_progress_bar.value = float(mini(progress, goal))
	_progress_label.text = "%d / %d enemies" % [mini(progress, goal), goal]

	var claimed := SaveManager.is_event_claimed(occ)
	var active := _event.is_active(now)
	var reached := progress >= goal
	if claimed:
		_status_label.text = "REWARD CLAIMED  ·  +%d ENERGY  +%d CORE" % [_event.reward_energy, _event.reward_core]
		_status_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6, 1))
		_claim_button.configure("CLAIMED", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE)
		_claim_button.set_enabled(false)
	elif reached and active:
		_status_label.text = "CACHE READY  ·  claim your reward"
		_status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
		_claim_button.configure("CLAIM REWARD", "+%d ENERGY  +%d CORE" % [_event.reward_energy, _event.reward_core], GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.MAGENTA)
		_claim_button.set_enabled(true)
	elif active:
		_status_label.text = "Destroy enemies in runs to fill the cache."
		_status_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
		_claim_button.configure("PLAY A RUN", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.CYAN)
		_claim_button.set_enabled(true)
	else:
		_status_label.text = "Invasion dormant. Return when the next window opens."
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8, 1))
		_claim_button.configure("BACK TO MENU", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE)
		_claim_button.set_enabled(true)


func _refresh_timer() -> void:
	if _event == null or _timer_label == null:
		return
	var now := _now()
	var remaining := _event.remaining_seconds(now)
	if _event.is_active(now):
		_timer_label.text = "ACTIVE  ·  %s LEFT" % EventData.format_countdown(remaining)
		_timer_label.add_theme_color_override("font_color", Color(1, 0.55, 0.9, 1))
	else:
		_timer_label.text = "NEXT WINDOW IN %s" % EventData.format_countdown(remaining)
		_timer_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 1))


func _on_claim() -> void:
	if _event == null:
		_on_back()
		return
	var now := _now()
	var occ := _event.occurrence_id(now)
	var progress := SaveManager.get_event_progress(occ)
	var active := _event.is_active(now)
	if active and progress >= _event.goal and not SaveManager.is_event_claimed(occ):
		if SaveManager.claim_event_reward(occ, _event.goal, _event.reward_energy, _event.reward_core):
			AudioManager.play_sfx("upgrade_select", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
			var haptics: HapticsService = PlatformServices.haptics
			if haptics != null and GameFeel.haptics_enabled:
				haptics.medium()
			_refresh()
			return
	if active:
		# Not yet ready: send the player into a run to earn progress.
		AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
		SceneRouter.go_to(SceneRouter.SCREEN_STAGE_MAP)
		return
	_on_back()


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)
