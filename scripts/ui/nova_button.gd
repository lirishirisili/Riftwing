class_name NovaButton
extends Control
## Rift Nova ultimate button: a charge ring that fills from kills / boss damage
## and pulses when ready. Emits `activated` only when fully charged.
##
## Presentation + input only; the run host owns the charge value and what the
## detonation does. Touch target stays >= 48 logical px (drawn smaller orb).

signal activated()

const _SIZE := Vector2(124, 124)

var ring_color: Color = Color(0.0, 0.84, 1.0, 1.0)

var _charge: float = 0.0
var _ready_pulse: float = 0.0
var _press_flash: float = 0.0
var _time: float = 0.0
var _button: Button
var _label: Label


func _ready() -> void:
	custom_minimum_size = _SIZE
	size = _SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_button.add_theme_stylebox_override(state, empty)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	_label = Label.new()
	_label.text = "NOVA"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 24)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	set_process(true)


## Charge fraction 0..1 (1 = ready).
func set_charge(fraction: float) -> void:
	var was_ready := is_charged()
	_charge = clampf(fraction, 0.0, 1.0)
	if is_charged() and not was_ready:
		_ready_pulse = 1.0


func is_charged() -> bool:
	return _charge >= 1.0


func _on_pressed() -> void:
	if not is_charged():
		AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_LOW)
		return
	_press_flash = 1.0
	GameFeel.haptic("medium")
	activated.emit()


func _process(delta: float) -> void:
	_time += delta
	if _ready_pulse > 0.0:
		_ready_pulse = maxf(0.0, _ready_pulse - delta * 1.5)
	if _press_flash > 0.0:
		_press_flash = maxf(0.0, _press_flash - delta * 3.0)
	if _label != null:
		_label.modulate = Color(1, 1, 1, 1.0 if is_charged() else 0.45)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.4
	var ring := ring_color
	if _press_flash > 0.0:
		ring = ring.lerp(Color.WHITE, _press_flash * 0.8)
	draw_circle(c, radius + 8.0, Color(0.02, 0.05, 0.1, 0.78))
	# Track + fill arc (fills clockwise from the top).
	draw_arc(c, radius, 0.0, TAU, 56, Color(ring, 0.2), 8.0, true)
	if _charge > 0.0:
		draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * _charge, 56, ring, 8.0, true)
	if is_charged():
		# Ready: breathing halo + expanding ping so it reads from the corner of an eye.
		var breathe := 0.5 + 0.5 * sin(_time * 6.0)
		draw_circle(c, radius - 6.0, Color(ring, 0.18 + 0.18 * breathe))
		draw_arc(c, radius + 6.0 + 6.0 * breathe, 0.0, TAU, 56, Color(ring, 0.35 + 0.3 * breathe), 3.0, true)
		if _ready_pulse > 0.0:
			var r := radius + (1.0 - _ready_pulse) * 70.0
			draw_arc(c, r, 0.0, TAU, 56, Color(ring, _ready_pulse), 4.0, true)
