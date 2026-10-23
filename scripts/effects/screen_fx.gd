class_name ScreenFX
extends CanvasLayer
## Full-screen feedback layer for the run: flash, danger vignette, chromatic
## aberration, and shockwave ripples.
##
## Sits above the world and below the HUD (the run host bumps the HUD layer), so
## text never distorts. Two passes:
## - Overlay (no screen read): vignette + color flash. Cheap; every profile.
## - Distort (screen read): aberration + shockwave. Only visible while an effect
##   is live and never on the LOW profile.
## Timing uses real time so effects keep animating through hit-stop / slow-mo.
## Purely presentation: it never changes gameplay state.

const _DISTORT_SHADER := preload("res://assets/shaders/screen_distort.gdshader")
const _OVERLAY_SHADER := preload("res://assets/shaders/screen_overlay.gdshader")

## Hard ceilings so a stack of events can never white-out the playfield
## (enemy bullets must stay readable).
const _MAX_FLASH_ALPHA := 0.42
const _MAX_ABERRATION := 0.018

var _distort: ColorRect
var _overlay: ColorRect
var _distort_mat: ShaderMaterial
var _overlay_mat: ShaderMaterial

var _flash_color: Color = Color(1, 1, 1, 0)
var _flash_peak: float = 0.0
var _flash_left: float = 0.0
var _flash_total: float = 0.0

var _ab_peak: float = 0.0
var _ab_left: float = 0.0
var _ab_total: float = 0.0

var _wave_center_uv: Vector2 = Vector2(0.5, 0.5)
var _wave_left: float = 0.0
var _wave_total: float = 0.0
var _wave_strength: float = 0.0

## Persistent danger level (0..1), e.g. low HP. Pulses gently when > 0.
var _danger: float = 0.0
var _danger_time: float = 0.0
var _last_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_distort = _make_rect(_DISTORT_SHADER)
	_distort_mat = _distort.material as ShaderMaterial
	_overlay = _make_rect(_OVERLAY_SHADER)
	_overlay_mat = _overlay.material as ShaderMaterial
	_distort.visible = false
	_overlay.visible = false
	_last_usec = Time.get_ticks_usec()
	GameFeel.register_screen_fx(self)


func _exit_tree() -> void:
	GameFeel.register_screen_fx(null)


func _make_rect(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(rect)
	return rect


## Brief full-screen tint (white for blasts, red for damage).
func flash(color: Color, alpha: float, seconds: float) -> void:
	var a := clampf(alpha, 0.0, _MAX_FLASH_ALPHA)
	if a <= _current_flash_alpha():
		return
	_flash_color = color
	_flash_peak = a
	_flash_total = maxf(0.01, seconds)
	_flash_left = _flash_total


## RGB channel split that eases back to zero.
func aberrate(amount: float, seconds: float) -> void:
	if GameFeel.quality == GameFeel.Quality.LOW:
		return
	var a := clampf(amount, 0.0, _MAX_ABERRATION)
	if a <= _current_aberration():
		return
	_ab_peak = a
	_ab_total = maxf(0.01, seconds)
	_ab_left = _ab_total


## Expanding ripple centered on a world position.
func shockwave(world_pos: Vector2, seconds: float = 0.7, strength: float = 0.035) -> void:
	if GameFeel.quality == GameFeel.Quality.LOW:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var screen := vp.get_canvas_transform() * world_pos
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_wave_center_uv = Vector2(screen.x / size.x, screen.y / size.y)
	_wave_total = maxf(0.05, seconds)
	_wave_left = _wave_total
	_wave_strength = strength if GameFeel.quality == GameFeel.Quality.HIGH else strength * 0.6


## Persistent danger vignette (0 = off). Used for low HP.
func set_danger(level: float) -> void:
	_danger = clampf(level, 0.0, 1.0)


func is_distort_active() -> bool:
	return _distort.visible


func _current_flash_alpha() -> float:
	if _flash_left <= 0.0 or _flash_total <= 0.0:
		return 0.0
	return _flash_peak * (_flash_left / _flash_total)


func _current_aberration() -> float:
	if _ab_left <= 0.0 or _ab_total <= 0.0:
		return 0.0
	var t := _ab_left / _ab_total
	return _ab_peak * t * t


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_usec) / 1000000.0, 0.0, 0.1)
	_last_usec = now
	_flash_left = maxf(0.0, _flash_left - dt)
	_ab_left = maxf(0.0, _ab_left - dt)
	_wave_left = maxf(0.0, _wave_left - dt)
	_danger_time += dt

	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(1.0, size.y)

	# Overlay: vignette + flash.
	var vig := 0.0
	if _danger > 0.0:
		vig = _danger * (0.55 + 0.25 * sin(_danger_time * 5.0))
	var flash_a := _current_flash_alpha()
	_overlay.visible = vig > 0.001 or flash_a > 0.001
	if _overlay.visible:
		_overlay_mat.set_shader_parameter("vignette", vig)
		_overlay_mat.set_shader_parameter("flash_color", Color(_flash_color, flash_a))
		_overlay_mat.set_shader_parameter("aspect", aspect)

	# Distort: aberration + shockwave.
	var ab := _current_aberration()
	var wave_on := _wave_left > 0.0
	_distort.visible = (ab > 0.0005 or wave_on) and GameFeel.quality != GameFeel.Quality.LOW
	if _distort.visible:
		_distort_mat.set_shader_parameter("aberration", ab)
		_distort_mat.set_shader_parameter("aspect", aspect)
		if wave_on:
			var p := 1.0 - _wave_left / _wave_total
			_distort_mat.set_shader_parameter("wave_center", _wave_center_uv)
			_distort_mat.set_shader_parameter("wave_radius", ease(p, 0.6) * 1.1)
			_distort_mat.set_shader_parameter("wave_strength", _wave_strength * (1.0 - p))
		else:
			_distort_mat.set_shader_parameter("wave_strength", 0.0)
