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
const _BAR_TOP := 44.0
const _BAR_HEIGHT := 26.0
const _BAR_MARGIN_X := 14.0
const _SEG_GAP := 4.0
const _CHROME_PAD := 6.0


func _ready() -> void:
	visible = false
	_warning.visible = false
	set_process(true)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Keep the bar below notches / cutouts and the compact top HUD chips.
func _apply_safe_area() -> void:
	var safe := SafeArea.get_logical_rect(get_tree())
	var vp := get_viewport_rect().size
	# Sit under score / pause chips (~96px) so the boss bar owns the top-center lane.
	var top := 108.0 + safe.position.y
	offset_top = top
	offset_bottom = top + 96.0
	# Leave ~240px per side for SCORE + pause chips so the bar never covers them.
	var half_w := clampf(vp.x * 0.5 - 250.0, 200.0, 300.0)
	offset_left = -half_w
	offset_right = half_w
	# Warning sits mid-upper viewport (not a fixed offset that drifts on tall phones).
	if _warning != null:
		var warn_y := vp.y * 0.38 - top
		_warning.offset_top = warn_y - 120.0
		_warning.offset_bottom = warn_y + 120.0
		_warning.offset_left = -mini(420.0, vp.x * 0.42)
		_warning.offset_right = mini(420.0, vp.x * 0.42)
	# Name / phase stay inside the narrowed bar.
	if _name_label != null:
		_name_label.offset_left = 10.0
		_name_label.offset_right = maxf(half_w * 2.0 - 140.0, 180.0)
		_name_label.clip_text = true
	if _phase_label != null:
		_phase_label.offset_left = -128.0
		_phase_label.offset_right = -8.0


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
	var chrome := Rect2(x0 - _CHROME_PAD, y0 - _CHROME_PAD, w + _CHROME_PAD * 2.0, _BAR_HEIGHT + _CHROME_PAD * 2.0)
	# Angular chrome plate (VOID TITAN reference frame).
	_draw_chrome_plate(chrome)
	var seg_w := (w - _SEG_GAP * float(_segment_count - 1)) / float(_segment_count)
	# Segments fill right-to-left as health drops. A segment is lit when the
	# health fraction covers its left edge.
	var fill := Palette.get_color("magenta") if _phase >= 2 else Palette.get_color("purple")
	var lost := Palette.get_color("danger")
	lost.a = 0.16
	var lit_segments := _display_fraction * float(_segment_count)
	for i in _segment_count:
		var sx := x0 + float(i) * (seg_w + _SEG_GAP)
		var seg := Rect2(sx, y0, seg_w, _BAR_HEIGHT)
		var covered := float(i) < lit_segments
		if covered:
			# Partial shading on the boundary segment.
			var frac := clampf(lit_segments - float(i), 0.0, 1.0)
			draw_rect(seg, Color(fill.r * 0.28, fill.g * 0.22, fill.b * 0.45, 0.55))
			var lit := Rect2(sx, y0, seg_w * frac, _BAR_HEIGHT)
			draw_rect(lit, Color(fill.r, fill.g, fill.b, 0.35))
			draw_rect(lit.grow(-1.5), fill)
			# Soft top highlight for segmented "chip" read.
			draw_rect(Rect2(sx + 1.0, y0 + 2.0, maxf(0.0, seg_w * frac - 2.0), 4.0), Color(1, 1, 1, 0.18))
		else:
			draw_rect(seg, lost)
			draw_rect(seg.grow(-1.0), Color(0.04, 0.02, 0.08, 0.55))
	# Outer neon rim.
	draw_rect(chrome.grow(1.0), Palette.get_color("cyan"), false, 2.0)
	# Phase-2 danger accent on the rim.
	if _phase >= 2:
		draw_rect(chrome, Palette.get_color("danger"), false, 1.5)


func _draw_chrome_plate(chrome: Rect2) -> void:
	# Faceted dark plate with cyan edge glow (reference boss HUD).
	draw_rect(chrome.grow(3.0), Color(0.0, 0.55, 0.85, 0.16))
	draw_rect(chrome, Color(0.02, 0.05, 0.1, 0.92))
	# Inner bevel line.
	draw_rect(chrome.grow(-2.0), Color(0.0, 0.72, 0.95, 0.35), false, 1.5)
	# Corner ticks for angular chrome read.
	var tick := 10.0
	var c := Palette.get_color("cyan")
	c.a = 0.75
	draw_line(chrome.position, chrome.position + Vector2(tick, 0.0), c, 2.0, true)
	draw_line(chrome.position, chrome.position + Vector2(0.0, tick), c, 2.0, true)
	var tr := Vector2(chrome.end.x, chrome.position.y)
	draw_line(tr, tr + Vector2(-tick, 0.0), c, 2.0, true)
	draw_line(tr, tr + Vector2(0.0, tick), c, 2.0, true)
	var bl := Vector2(chrome.position.x, chrome.end.y)
	draw_line(bl, bl + Vector2(tick, 0.0), c, 2.0, true)
	draw_line(bl, bl + Vector2(0.0, -tick), c, 2.0, true)
	var br := chrome.end
	draw_line(br, br + Vector2(-tick, 0.0), c, 2.0, true)
	draw_line(br, br + Vector2(0.0, -tick), c, 2.0, true)
