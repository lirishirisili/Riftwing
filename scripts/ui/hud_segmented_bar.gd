class_name HudSegmentedBar
extends Control
## Compact segmented bar for health / XP / shield-style HUD readouts.
##
## Drawn with a dark track, cyan or purple fill, and optional low-state pulse.
## Layout is driven by anchors; no gameplay logic lives here.

@export var segment_count: int = 10
@export var fill_color: Color = Color(0, 0.84, 1, 1)
@export var track_color: Color = Color(0.02, 0.06, 0.12, 0.9)
@export var low_threshold: float = 0.25
@export var low_color: Color = Color(1, 0.23, 0.31, 1)

var _fraction: float = 1.0
var _display: float = 1.0
var _damage_flash: float = 0.0
var _low_pulse: float = 0.0


func set_fraction(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if next < _fraction - 0.001:
		_damage_flash = 1.0
	_fraction = next


func set_fill_color(color: Color) -> void:
	fill_color = color


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_display = move_toward(_display, _fraction, delta * 1.2 + absf(_display - _fraction) * delta * 8.0)
	if _damage_flash > 0.0:
		_damage_flash = maxf(0.0, _damage_flash - delta * 3.5)
	_low_pulse += delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Neon track with soft outer glow (reference segmented bars).
	draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(fill_color.r, fill_color.g, fill_color.b, 0.12))
	draw_rect(r, track_color)
	var segs := maxi(1, segment_count)
	var gap := 3.0
	var seg_w := (size.x - gap * float(segs - 1)) / float(segs)
	var lit := _display * float(segs)
	var col := fill_color
	if _fraction <= low_threshold:
		var pulse := 0.55 + 0.45 * absf(sin(_low_pulse * 7.0))
		col = fill_color.lerp(low_color, pulse)
	if _damage_flash > 0.0:
		col = col.lerp(Color.WHITE, _damage_flash * 0.65)
	for i in segs:
		var sx := float(i) * (seg_w + gap)
		var seg := Rect2(sx, 2.0, seg_w, size.y - 4.0)
		if float(i) < lit:
			var frac := clampf(lit - float(i), 0.0, 1.0)
			var filled := Rect2(sx, 2.0, seg_w * frac, size.y - 4.0)
			draw_rect(filled, Color(col.r, col.g, col.b, 0.35))
			draw_rect(filled.grow(-1.0), col)
		else:
			draw_rect(seg, Color(col.r, col.g, col.b, 0.14))
	draw_rect(r, Color(fill_color.r, fill_color.g, fill_color.b, 0.7), false, 2.0)
