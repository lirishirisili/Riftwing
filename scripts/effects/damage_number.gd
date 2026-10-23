class_name DamageNumber
extends Node2D
## Pooled floating damage number. Pops in, rises and fades from the hit point,
## then returns itself to the pool. Crits are gold, larger, and marked "!".
## Uses a real Label (never baked text) per docs/01_VISUAL_DIRECTION.md.
## Never freed at runtime.

const LIFETIME := 0.6
const CRIT_LIFETIME := 0.8
const RISE := 46.0
## Horizontal scatter so a stream of hits does not stack into one smear.
const _JITTER_X := 22.0

enum Style { NONE, SMALL, MEDIUM, BIG, CRIT }

var release_callback: Callable = Callable()

var _age: float = 0.0
var _life: float = LIFETIME
var _active: bool = false
var _origin: Vector2 = Vector2.ZERO
var _crit: bool = false
## Last applied label style; theme overrides are only rewritten on change.
var _style: int = Style.NONE

@onready var _label: Label = $Label


func spawn(world_pos: Vector2, amount: int, is_crit: bool = false) -> void:
	_origin = world_pos + Vector2(randf_range(-_JITTER_X, _JITTER_X), 0.0)
	global_position = _origin
	_age = 0.0
	_crit = is_crit
	_life = CRIT_LIFETIME if is_crit else LIFETIME
	_active = true
	visible = true
	scale = Vector2.ONE * (1.6 if is_crit else 1.3)
	set_process(true)
	if _label == null:
		return
	if is_crit:
		_label.text = "%d!" % amount
		_apply_style(Style.CRIT)
	else:
		_label.text = "+%d" % amount if amount >= 100 else str(amount)
		# HIGH quality: warmer / larger pops like the reference score flashes.
		if GameFeel.quality == GameFeel.Quality.HIGH and amount >= 40:
			_apply_style(Style.BIG)
		elif GameFeel.quality == GameFeel.Quality.MEDIUM:
			_apply_style(Style.MEDIUM)
		else:
			_apply_style(Style.SMALL)


func _apply_style(style: int) -> void:
	if style != _style:
		_style = style
		var size := 28
		match style:
			Style.CRIT: size = 48
			Style.BIG: size = 42
			Style.MEDIUM: size = 34
		_label.add_theme_font_size_override("font_size", size)
	match style:
		Style.CRIT:
			_label.modulate = Palette.get_color("gold", Color(1.0, 0.84, 0.25))
		Style.BIG:
			_label.modulate = Palette.get_color("orange", Color(1.0, 0.55, 0.12))
		_:
			_label.modulate = Palette.get_color("white", Color.WHITE)


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= _life:
		_release()
		return
	var t := clampf(_age / _life, 0.0, 1.0)
	global_position = _origin + Vector2(0.0, -RISE * ease(t, 0.4) * (1.4 if _crit else 1.0))
	# Pop: overshoot then settle within the first ~20% of the life.
	var settle := clampf(t / 0.2, 0.0, 1.0)
	var start := 1.6 if _crit else 1.3
	scale = Vector2.ONE * lerpf(start, 1.0, ease(settle, 0.5))
	if _label != null:
		_label.modulate.a = 1.0 - t * t


func pool_reset() -> void:
	_age = 0.0
	_active = false


func pool_disable() -> void:
	_active = false
	visible = false
	set_process(false)


func _release() -> void:
	_active = false
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
