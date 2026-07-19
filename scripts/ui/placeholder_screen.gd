class_name PlaceholderScreen
extends Control
## Coming-soon stand-in with MetaScreenShell + glow BACK CTA.

const _GLOW := preload("res://scenes/ui/chrome/glow_cta_button.tscn")

@onready var _shell: MetaScreenShell = %Shell

var _pending_title := "COMING SOON"
var _pending_subtitle := "This feature arrives in a future update."
var _title: Label
var _subtitle: Label


func receive_payload(payload: Dictionary) -> void:
	if payload.has("title"):
		_pending_title = String(payload["title"])
	if payload.has("subtitle"):
		_pending_subtitle = String(payload["subtitle"])
	if _title != null:
		_title.text = _pending_title
	if _subtitle != null:
		_subtitle.text = _pending_subtitle


func _ready() -> void:
	var body := _shell.get_body()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"NeonPanel"
	body.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	_title = Label.new()
	_title.text = _pending_title
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 56)
	col.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = _pending_subtitle
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 28)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.65, 1, 1))
	col.add_child(_subtitle)

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer2)

	var back := _GLOW.instantiate() as GlowCtaButton
	body.add_child(back)
	back.configure("BACK TO MENU", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN)
	back.pressed.connect(_on_back)


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)
