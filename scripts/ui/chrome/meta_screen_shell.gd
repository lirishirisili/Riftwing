class_name MetaScreenShell
extends Control
## Shared cinematic backdrop + tech header for meta screens (map/hangar/settings/…).
## Put screen content under %Body. Optional trailing control via set_trailing().

const _BASE_PADDING := 32.0
const _SCROLL_SPEED := 12.0

@onready var _parallax: ParallaxBackground = $Background
@onready var _safe: MarginContainer = %Safe
@onready var _energy_value: Label = %EnergyValue
@onready var _core_value: Label = %CoreValue
@onready var _brand: Label = %BrandLabel
@onready var _trailing: Control = %TrailingSlot
@onready var _body: VBoxContainer = %Body

var _scroll_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _brand != null:
		_brand.text = "RIFTWING"
	get_viewport().size_changed.connect(_on_viewport_changed)
	_on_viewport_changed()
	refresh_currencies()
	if not SaveManager.currencies_changed.is_connected(_on_currencies_changed):
		SaveManager.currencies_changed.connect(_on_currencies_changed)
	set_process(true)


func _on_viewport_changed() -> void:
	apply_safe_area()
	_fit_backdrop()


## Cover expanded viewports (tablet / tall phones) so parallax plates never leave black bands.
func _fit_backdrop() -> void:
	var vp := get_viewport_rect().size
	var cover := Vector2(maxf(vp.x + 240.0, 1400.0), maxf(vp.y + 480.0, 2400.0))
	for path in ["Background/Keyart/Tex", "Background/Stars/Tex", "Background/Nebula/Tex"]:
		var tex := get_node_or_null(path) as Control
		if tex == null:
			continue
		tex.position = Vector2.ZERO
		tex.size = cover


func _process(delta: float) -> void:
	_scroll_time += delta
	if _parallax != null:
		_parallax.scroll_offset.y += delta * _SCROLL_SPEED


func get_body() -> VBoxContainer:
	return _body


func set_trailing(node: Control) -> void:
	if _trailing == null or node == null:
		return
	for child in _trailing.get_children():
		_trailing.remove_child(child)
		child.queue_free()
	_trailing.add_child(node)


func refresh_currencies() -> void:
	if _energy_value != null:
		_energy_value.text = _format_int(SaveManager.get_rift_energy())
	if _core_value != null:
		_core_value.text = _format_int(SaveManager.get_rift_core())


func apply_safe_area() -> void:
	if _safe == null:
		return
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport_rect().size
	_safe.add_theme_constant_override("margin_left", int(_BASE_PADDING + safe.position.x))
	_safe.add_theme_constant_override("margin_top", int(_BASE_PADDING + safe.position.y))
	_safe.add_theme_constant_override("margin_right", int(_BASE_PADDING + (full.x - (safe.position.x + safe.size.x))))
	_safe.add_theme_constant_override("margin_bottom", int(_BASE_PADDING + 24.0 + (full.y - (safe.position.y + safe.size.y))))


func _on_currencies_changed(_e: int, _c: int) -> void:
	refresh_currencies()


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
