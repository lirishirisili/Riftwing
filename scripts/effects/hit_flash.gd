class_name HitFlash
extends Node2D
## Pooled impact flash: a quick expanding ring + a short-lived spark burst drawn
## at a projectile hit. Cheap and additive; returns itself to the pool when its
## brief lifetime expires. Never freed at runtime.

const LIFETIME := 0.22

var release_callback: Callable = Callable()

var _age: float = 0.0
var _color: Color = Color.WHITE
var _active: bool = false
var _sparks: int = 0

@onready var _particles: CPUParticles2D = $Sparks


## Activates the flash at a world position with a tint. `spark_count` comes from
## the current quality budget (0 disables the particle burst).
func spawn(world_pos: Vector2, color: Color, spark_count: int) -> void:
	global_position = world_pos
	_color = color
	_age = 0.0
	_active = true
	_sparks = spark_count
	visible = true
	set_process(true)
	if _particles != null:
		_particles.color = color
		if spark_count > 0:
			_particles.amount = spark_count
			_particles.emitting = true
		else:
			_particles.emitting = false
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= LIFETIME:
		_release()
		return
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	var radius := lerpf(6.0, 34.0, t)
	var alpha := 1.0 - t
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(_color, alpha * 0.9), 3.0, true)
	draw_circle(Vector2.ZERO, lerpf(7.0, 1.0, t), Color(1, 1, 1, alpha))


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
