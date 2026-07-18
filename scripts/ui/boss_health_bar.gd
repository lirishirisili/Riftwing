class_name BossHealthBar
extends Control
## Segmented boss health bar for the top safe area.
##
## Draws a data-driven number of segments (from BossData) that deplete right to
## left, plus a real boss-name Label and a phase pip — text is a real Control,
## never baked art (CLAUDE.md). The fill color shifts to the danger role in
## phase 2 so the player reads the escalation. A separate WARNING banner is shown
## during the boss entrance. Segments are drawn within `_bar_rect`, laid out via
## anchors so the bar scales across aspect ratios rather than fixed coordinates.

@onready var _name_label: Label = $Name
@onready var _phase_label: Label = $Phase
@onready var _warning: Label = $Warning

var _segment_count: int = 20
var _fraction: float = 1.0
var _display_fraction: float = 1.0
var _phase: int = 1
var _warn_pulse: float = 0.0
var _warning_active: bool = false

## Vertical band (within this Control) where the segment bar is drawn.
const _BAR_TOP := 64.0
const _BAR_HEIGHT := 34.0
const _BAR_MARGIN_X := 12.0
const _SEG_GAP := 4.0


func _ready() -> void:
	visible = false
	_warning.visible = false
	set_process(true)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Keep the bar below notches / cutouts on 19.5:9 and 20:9 devices.
func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var top := 40.0 + safe.position.y
	offset_top = top
	offset_bottom = top + 110.0
	# Centered ±480 on the base width; widen slightly on expanded viewports.
	var half_w := mini(480.0, get_viewport_rect().size.x * 0.44)
	offset_left = -half_w
	offset_right = half_w


## Sets the boss name and segment count from BossData, then shows the bar.
func setup(boss_name: String, segments: int) -> void:
	_name_label.text = boss_name
	_segment_count = maxi(1, segments)
	_fraction = 1.0
	_display_fraction = 1.0
	_phase = 1
	visible = true
	_phase_label.text = "PHASE 1"
	queue_redraw()


func set_health(current: float, maximum: float) -> void:
	_fraction = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)


func set_phase(phase: int) -> void:
	_phase = phase
	_phase_label.text = "PHASE %d" % phase
	queue_redraw()


## Shows the pulsing entrance warning banner with the boss name.
func show_warning(boss_name: String) -> void:
	_warning.text = "! WARNING !\n%s" % boss_name
	_warning.visible = true
	_warning_active = true
	_warn_pulse = 0.0


func hide_warning() -> void:
	_warning.visible = false
	_warning_active = false


func _process(delta: float) -> void:
	# Ease the displayed fill toward the true value for a smooth drain, then
	# redraw. Cheap enough to run every frame the bar is visible.
	if visible:
		_display_fraction = move_toward(_display_fraction, _fraction, delta * 0.9 + absf(_display_fraction - _fraction) * delta * 6.0)
		queue_redraw()
	if _warning_active:
		_warn_pulse += delta
		_warning.modulate.a = 0.55 + 0.45 * absf(sin(_warn_pulse * 6.0))


func _draw() -> void:
	if not visible:
		return
	var w := size.x - _BAR_MARGIN_X * 2.0
	var x0 := _BAR_MARGIN_X
	var y0 := _BAR_TOP
	# Backing track.
	draw_rect(Rect2(x0 - 4.0, y0 - 4.0, w + 8.0, _BAR_HEIGHT + 8.0), Color(0.02, 0.06, 0.12, 0.85))
	var seg_w := (w - _SEG_GAP * float(_segment_count - 1)) / float(_segment_count)
	# Segments fill right-to-left as health drops. A segment is lit when the
	# health fraction covers its left edge.
	var fill := Palette.get_color("magenta") if _phase >= 2 else Palette.get_color("purple")
	var lost := Palette.get_color("danger")
	lost.a = 0.18
	var lit_segments := _display_fraction * float(_segment_count)
	for i in _segment_count:
		var sx := x0 + float(i) * (seg_w + _SEG_GAP)
		var seg := Rect2(sx, y0, seg_w, _BAR_HEIGHT)
		var covered := float(i) < lit_segments
		if covered:
			# Partial shading on the boundary segment.
			var frac := clampf(lit_segments - float(i), 0.0, 1.0)
			draw_rect(seg, Color(fill.r * 0.35, fill.g * 0.35, fill.b * 0.5, 0.5))
			draw_rect(Rect2(sx, y0, seg_w * frac, _BAR_HEIGHT), fill)
		else:
			draw_rect(seg, lost)
	# Thin outline.
	draw_rect(Rect2(x0 - 4.0, y0 - 4.0, w + 8.0, _BAR_HEIGHT + 8.0), Palette.get_color("cyan"), false, 2.0)
