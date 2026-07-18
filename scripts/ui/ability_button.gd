class_name AbilityButton
extends Control
## Circular ability control with charge count + cooldown feedback.
##
## Emits `activated` when pressed with at least one charge and no cooldown.
## Visual only regarding combat — the run host decides what (if anything) happens.

signal activated()

@export var icon_texture: Texture2D
@export var ring_color: Color = Color(0, 0.84, 1, 1)
@export var max_charges: int = 3
@export var cooldown_seconds: float = 6.0

var _charges: int = 3
var _cooldown: float = 0.0
var _press_flash: float = 0.0
var _full_pulse: float = 0.0

@onready var _button: Button = $Hit
@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Count


func _ready() -> void:
	_charges = max_charges
	custom_minimum_size = Vector2(112, 112)
	if _icon != null and icon_texture != null:
		_icon.texture = icon_texture
	_button.pressed.connect(_on_pressed)
	_refresh_count()
	set_process(true)


func configure(charges: int, cooldown: float, tex: Texture2D, color: Color) -> void:
	max_charges = maxi(1, charges)
	_charges = max_charges
	cooldown_seconds = maxf(0.5, cooldown)
	ring_color = color
	if tex != null:
		icon_texture = tex
		if _icon != null:
			_icon.texture = tex
	_refresh_count()


func get_charges() -> int:
	return _charges


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
		if _cooldown <= 0.0:
			if _charges < max_charges:
				_charges = mini(max_charges, _charges + 1)
				_refresh_count()
			_full_pulse = 1.0
	if _press_flash > 0.0:
		_press_flash = maxf(0.0, _press_flash - delta * 4.0)
	if _full_pulse > 0.0:
		_full_pulse = maxf(0.0, _full_pulse - delta * 2.0)
	queue_redraw()


func _on_pressed() -> void:
	if _charges <= 0 or _cooldown > 0.0:
		AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_LOW)
		return
	_charges -= 1
	_cooldown = cooldown_seconds
	_press_flash = 1.0
	_refresh_count()
	AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null and GameFeel.haptics_enabled:
		haptics.light()
	activated.emit()


func _refresh_count() -> void:
	if _count != null:
		_count.text = str(_charges)
	_button.disabled = false


func _draw() -> void:
	var c := size * 0.5
	var radius := mini(size.x, size.y) * 0.42
	# Soft outer neon bloom + hex-ish tech ring (reference ability orbs).
	draw_circle(c, radius + 10.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.12))
	draw_circle(c, radius + 6.0, Color(0.02, 0.05, 0.1, 0.82))
	var ring := ring_color
	if _press_flash > 0.0:
		ring = ring.lerp(Color.WHITE, _press_flash * 0.7)
	elif _full_pulse > 0.0:
		ring = ring.lerp(Color(1, 0.85, 0.3, 1), _full_pulse * 0.5)
	draw_arc(c, radius + 2.0, 0.0, TAU, 56, Color(ring, 0.28), 10.0, true)
	draw_arc(c, radius, 0.0, TAU, 56, Color(ring, 0.45), 7.0, true)
	if _cooldown > 0.0 and cooldown_seconds > 0.0:
		var remain := _cooldown / cooldown_seconds
		draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - remain), 56, ring, 6.0, true)
	else:
		draw_arc(c, radius, 0.0, TAU, 56, ring, 5.5, true)
	# Tick marks for tech chrome.
	for i in 8:
		var a := float(i) * TAU / 8.0
		var p0 := c + Vector2.from_angle(a) * (radius - 4.0)
		var p1 := c + Vector2.from_angle(a) * (radius + 2.0)
		draw_line(p0, p1, Color(ring, 0.55), 2.0, true)
	if _charges <= 0:
		draw_circle(c, radius * 0.9, Color(0, 0, 0, 0.45))
