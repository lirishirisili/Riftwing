class_name GlowCtaButton
extends Control
## Reusable main-menu-style glow CTA: chrome SVG plate + empty Button + labels.
## Variants: primary (cyan hex), secondary (purple bar), nav (compact cyan hex).

signal pressed()

enum Variant { PRIMARY, SECONDARY, NAV }
enum Pulse { NONE, CYAN, MAGENTA }

const _TEX_PRIMARY := "res://assets/ui/chrome/cta_start_hex.svg"
const _TEX_SECONDARY := "res://assets/ui/chrome/cta_daily_bar.svg"
const _TEX_NAV := "res://assets/ui/chrome/cta_nav_hex.svg"

@export var variant: Variant = Variant.PRIMARY:
	set(v):
		variant = v
		_apply_variant()

@export var title: String = "ACTION":
	set(v):
		title = v
		_refresh_labels()

@export var subtitle: String = "":
	set(v):
		subtitle = v
		_refresh_labels()

@export var pulse: Pulse = Pulse.NONE
@export var chrome_modulate: Color = Color(1, 1, 1, 1):
	set(v):
		chrome_modulate = v
		if _chrome != null:
			_chrome.modulate = chrome_modulate
@export var min_height: float = 0.0:
	set(v):
		min_height = v
		_apply_variant()

@onready var _chrome: TextureRect = %Chrome
@onready var _button: Button = %Button
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _sub_row: HBoxContainer = %SubRow
@onready var _left_icon: TextureRect = %LeftIcon
@onready var _right_icon: TextureRect = %RightIcon
@onready var _content_row: HBoxContainer = %ContentRow

var _pulse_time := 0.0
var _left_tex: Texture2D
var _right_tex: Texture2D


func _ready() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _button != null:
		_button.pressed.connect(func() -> void: pressed.emit())
	_apply_variant()
	_refresh_labels()
	_refresh_icons()
	set_process(pulse != Pulse.NONE)


func _process(delta: float) -> void:
	if pulse == Pulse.NONE or _chrome == null:
		return
	_pulse_time += delta
	match pulse:
		Pulse.CYAN:
			var g := 0.92 + absf(sin(_pulse_time * 1.8)) * 0.08
			_chrome.modulate = Color(g, g, 1.0, 1.0) * chrome_modulate
		Pulse.MAGENTA:
			var g := 0.94 + absf(sin(_pulse_time * 1.35)) * 0.06
			_chrome.modulate = Color(1.0, g, 1.0, 1.0) * chrome_modulate
		_:
			_chrome.modulate = chrome_modulate


func configure(
	p_title: String,
	p_subtitle: String = "",
	p_variant: Variant = Variant.PRIMARY,
	p_pulse: Pulse = Pulse.NONE,
	p_min_height: float = -1.0
) -> void:
	title = p_title
	subtitle = p_subtitle
	variant = p_variant
	pulse = p_pulse
	if p_min_height >= 0.0:
		min_height = p_min_height
	set_process(pulse != Pulse.NONE)
	_apply_variant()
	_refresh_labels()


func set_icons(left: Texture2D, right: Texture2D = null) -> void:
	_left_tex = left
	_right_tex = right
	_refresh_icons()


func set_enabled(enabled: bool) -> void:
	if _button != null:
		_button.disabled = not enabled
	modulate.a = 1.0 if enabled else 0.55


func get_button() -> Button:
	return _button


func _apply_variant() -> void:
	if _chrome == null:
		return
	var path := _TEX_PRIMARY
	var height := 156.0
	var title_size := 44
	match variant:
		Variant.SECONDARY:
			path = _TEX_SECONDARY
			height = 108.0
			title_size = 28
		Variant.NAV:
			path = _TEX_NAV
			height = 104.0
			title_size = 26
		_:
			path = _TEX_PRIMARY
			height = 156.0
			title_size = 44
	if min_height > 0.0:
		height = min_height
		if height <= 72.0:
			title_size = 20
		elif height <= 96.0:
			title_size = 24
	custom_minimum_size = Vector2(0, height)
	if ResourceLoader.exists(path):
		_chrome.texture = load(path) as Texture2D
	_chrome.modulate = chrome_modulate
	if _title != null:
		_title.add_theme_font_size_override("font_size", title_size)
	if _button != null:
		_button.theme_type_variation = &"ButtonChrome"


func _refresh_labels() -> void:
	if _title != null:
		_title.text = title
	var has_sub := subtitle.strip_edges() != ""
	if _subtitle != null:
		_subtitle.text = subtitle
		_subtitle.visible = has_sub
	if _sub_row != null:
		_sub_row.visible = has_sub


func _refresh_icons() -> void:
	if _left_icon != null:
		_left_icon.visible = _left_tex != null
		_left_icon.texture = _left_tex
	if _right_icon != null:
		_right_icon.visible = _right_tex != null
		_right_icon.texture = _right_tex
