class_name SettingsScreen
extends Control
## Settings — MetaScreenShell + glow CTAs matching main-menu chrome.

const _GLOW := preload("res://scenes/ui/chrome/glow_cta_button.tscn")
const _VOL_STEP := 0.2

@onready var _shell: MetaScreenShell = %Shell

var _audio_btn: GlowCtaButton
var _music_btn: GlowCtaButton
var _sfx_btn: GlowCtaButton
var _quality_btn: GlowCtaButton
var _haptics_btn: GlowCtaButton
var _reset_btn: GlowCtaButton
var _back_btn: GlowCtaButton
var _reset_hint: Label
var _reset_armed := false


func _ready() -> void:
	var body := _shell.get_body()
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	body.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "AUDIO · FEEL · PROGRESS"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.55, 1, 1))
	body.add_child(subtitle)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NeonPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	_audio_btn = _make_row(col, "AUDIO", "", GlowCtaButton.Variant.NAV)
	_music_btn = _make_row(col, "MUSIC", "", GlowCtaButton.Variant.NAV)
	_sfx_btn = _make_row(col, "SFX", "", GlowCtaButton.Variant.NAV)
	_quality_btn = _make_row(col, "EFFECTS", "", GlowCtaButton.Variant.NAV)
	_haptics_btn = _make_row(col, "HAPTICS", "", GlowCtaButton.Variant.NAV)
	_reset_btn = _make_row(col, "RESET PROGRESS", "", GlowCtaButton.Variant.SECONDARY)

	_reset_hint = Label.new()
	_reset_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_hint.add_theme_font_size_override("font_size", 20)
	_reset_hint.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 1))
	col.add_child(_reset_hint)

	_back_btn = _GLOW.instantiate() as GlowCtaButton
	body.add_child(_back_btn)
	_back_btn.configure("BACK TO MENU", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN)

	_audio_btn.pressed.connect(_on_audio)
	_music_btn.pressed.connect(_on_music)
	_sfx_btn.pressed.connect(_on_sfx)
	_quality_btn.pressed.connect(_on_quality)
	_haptics_btn.pressed.connect(_on_haptics)
	_reset_btn.pressed.connect(_on_reset)
	_back_btn.pressed.connect(_on_back)

	AudioManager.play_music("menu")
	_refresh()


func _make_row(parent: Node, title: String, sub: String, variant: GlowCtaButton.Variant) -> GlowCtaButton:
	var btn := _GLOW.instantiate() as GlowCtaButton
	parent.add_child(btn)
	btn.configure(title, sub, variant)
	return btn


func _refresh() -> void:
	_audio_btn.configure("AUDIO:  %s" % ("ON" if AudioManager.enabled else "OFF"), "", GlowCtaButton.Variant.NAV)
	_music_btn.configure("MUSIC:  %d%%" % int(round(AudioManager.music_linear * 100.0)), "", GlowCtaButton.Variant.NAV)
	_sfx_btn.configure("SFX:  %d%%" % int(round(AudioManager.sfx_linear * 100.0)), "", GlowCtaButton.Variant.NAV)
	_quality_btn.configure("EFFECTS:  %s" % GameFeel.quality_name(), "", GlowCtaButton.Variant.NAV)
	_haptics_btn.configure("HAPTICS:  %s" % ("ON" if GameFeel.haptics_enabled else "OFF"), "", GlowCtaButton.Variant.NAV)
	_reset_btn.configure(
		"RESET PROGRESS?  TAP AGAIN" if _reset_armed else "RESET PROGRESS",
		"",
		GlowCtaButton.Variant.SECONDARY
	)
	_reset_hint.text = "Rift Energy %d · Rift Core %d · Best %d" % [
		SaveManager.get_rift_energy(), SaveManager.get_rift_core(), SaveManager.get_best_score()]


func _on_audio() -> void:
	AudioManager.set_enabled(not AudioManager.enabled)
	if AudioManager.enabled:
		AudioManager.play_music("menu")
	_click()
	_refresh()


func _on_music() -> void:
	var next := AudioManager.music_linear + _VOL_STEP
	if next > 1.001:
		next = 0.0
	AudioManager.set_music_volume(next)
	_click()
	_refresh()


func _on_sfx() -> void:
	var next := AudioManager.sfx_linear + _VOL_STEP
	if next > 1.001:
		next = 0.0
	AudioManager.set_sfx_volume(next)
	_click()
	_refresh()


func _on_quality() -> void:
	GameFeel.cycle_quality()
	_click()
	_refresh()


func _on_haptics() -> void:
	GameFeel.set_haptics_enabled(not GameFeel.haptics_enabled)
	_click()
	_refresh()


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_click()
		_refresh()
		return
	SaveManager.reset()
	_reset_armed = false
	_click()
	_refresh()


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if GameFeel.haptics_enabled and haptics != null:
		haptics.light()
