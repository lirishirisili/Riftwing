class_name HeaderBackButton
extends Button
## Compact neon Back control for the MetaScreenShell header trailing slot.
##
## Replaces the full-size GlowCtaButton that overflowed the crowded header and
## overlapped the currency chips. Fixed compact bounds (no glow bleed), a real
## >=48px touch target, and a clear chevron + label. Emits the standard Button
## `pressed` signal so screens wire it exactly like the old button.

const _CYAN := Color(0.35, 0.92, 1.0, 1.0)


func _init() -> void:
	text = "‹  BACK"
	# Comfortable touch target that still fits the 76px header content band.
	custom_minimum_size = Vector2(132, 64)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip_text = true
	add_theme_font_size_override("font_size", 24)
	add_theme_color_override("font_color", _CYAN)
	add_theme_color_override("font_hover_color", Color(0.7, 0.98, 1.0, 1.0))
	add_theme_color_override("font_pressed_color", Color(0.85, 1.0, 1.0, 1.0))
	add_theme_stylebox_override("normal", _make_style(Color(0.04, 0.09, 0.17, 0.92), Color(0, 0.78, 0.98, 0.7)))
	add_theme_stylebox_override("hover", _make_style(Color(0.06, 0.13, 0.24, 0.96), Color(0.2, 0.9, 1.0, 0.95)))
	add_theme_stylebox_override("pressed", _make_style(Color(0.02, 0.06, 0.12, 0.98), Color(0.4, 0.98, 1.0, 1.0)))


func _make_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = border
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_right = 2
	s.corner_radius_bottom_left = 12
	s.content_margin_left = 14
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s
