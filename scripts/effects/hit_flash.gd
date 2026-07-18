class_name HitFlash
extends Node2D
## Pooled impact / muzzle / shield flash. Expanding ring + spark burst; returns
## to the pool when lifetime expires. Never freed at runtime.

enum Style { IMPACT, MUZZLE, SHIELD }

const LIFETIME_IMPACT := 0.22
const LIFETIME_MUZZLE := 0.12
const LIFETIME_SHIELD := 0.32

var release_callback: Callable = Callable()

var _age: float = 0.0
var _lifetime: float = LIFETIME_IMPACT
var _color: Color = Color.WHITE
var _active: bool = false
var _sparks: int = 0
var _style: int = Style.IMPACT

@onready var _particles: CPUParticles2D = $Sparks


## Activates the flash at a world position with a tint. `spark_count` comes from
## the current quality budget (0 disables the particle burst).
func spawn(world_pos: Vector2, color: Color, spark_count: int, style: int = Style.IMPACT) -> void:
	global_position = world_pos
	_color = color
	_age = 0.0
	_active = true
	_sparks = spark_count
	_style = style
	match style:
		Style.MUZZLE:
			_lifetime = LIFETIME_MUZZLE
		Style.SHIELD:
			_lifetime = LIFETIME_SHIELD
		_:
			_lifetime = LIFETIME_IMPACT
	visible = true
	set_process(true)
	if _particles != null:
		_particles.color = color
		if spark_count > 0 and style != Style.MUZZLE:
			_particles.amount = spark_count
			_particles.emitting = true
		else:
			_particles.emitting = false
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= _lifetime:
		_release()
		return
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var alpha := 1.0 - t
	match _style:
		Style.MUZZLE:
			var r := lerpf(4.0, 22.0, t)
			draw_circle(Vector2.ZERO, lerpf(10.0, 2.0, t), Color(1, 1, 1, alpha))
			draw_circle(Vector2.ZERO, r, Color(_color, alpha * 0.55))
			draw_arc(Vector2.ZERO, r * 1.15, 0.0, TAU, 20, Color(_color, alpha * 0.8), 2.0, true)
		Style.SHIELD:
			var r2 := lerpf(18.0, 70.0, t)
			draw_arc(Vector2.ZERO, r2, 0.0, TAU, 36, Color(_color, alpha * 0.85), 4.0, true)
			draw_arc(Vector2.ZERO, r2 * 0.72, 0.0, TAU, 28, Color(1, 1, 1, alpha * 0.45), 2.0, true)
		_:
			var radius := lerpf(6.0, 38.0, t)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(_color, alpha * 0.9), 3.0, true)
			draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 20, Color(1, 1, 1, alpha * 0.55), 2.0, true)
			draw_circle(Vector2.ZERO, lerpf(8.0, 1.0, t), Color(1, 1, 1, alpha))


func pool_reset() -> void:
	_age = 0.0
	_active = false


func pool_disable() -> void:
	_active = false
	visible = false
	set_process(false)
	if _particles != null:
		_particles.emitting = false


func _release() -> void:
	_active = false
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
