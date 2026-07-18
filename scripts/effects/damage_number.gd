class_name DamageNumber
extends Node2D
## Pooled floating damage number. Rises and fades from the hit point, then
## returns itself to the pool. Uses a real Label (never baked text) per
## docs/01_VISUAL_DIRECTION.md. Never freed at runtime.

const LIFETIME := 0.6
const RISE := 46.0

var release_callback: Callable = Callable()

var _age: float = 0.0
var _active: bool = false
var _origin: Vector2 = Vector2.ZERO

@onready var _label: Label = $Label


func spawn(world_pos: Vector2, amount: int) -> void:
	_origin = world_pos
	global_position = world_pos
	_age = 0.0
	_active = true
	visible = true
	set_process(true)
	if _label != null:
		_label.text = "+%d" % amount if amount >= 100 else str(amount)
		# HIGH quality: warmer / larger pops like the reference score flashes.
		if GameFeel.quality == GameFeel.Quality.HIGH and amount >= 40:
			_label.add_theme_font_size_override("font_size", 42)
			_label.modulate = Palette.get_color("orange", Color(1.0, 0.55, 0.12))
		elif GameFeel.quality == GameFeel.Quality.MEDIUM:
			_label.add_theme_font_size_override("font_size", 34)
			_label.modulate = Palette.get_color("white", Color.WHITE)
		else:
			_label.add_theme_font_size_override("font_size", 28)
			_label.modulate = Palette.get_color("white", Color.WHITE)


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= LIFETIME:
		_release()
		return
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	global_position = _origin + Vector2(0.0, -RISE * ease(t, 0.4))
	if _label != null:
		_label.modulate.a = 1.0 - t


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
