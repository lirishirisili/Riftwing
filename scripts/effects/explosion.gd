class_name Explosion
extends Node2D
## Pooled explosion: combines a sprite ring (shockwave placeholder), a procedural
## expanding radial ring, a light flash, and a CPU particle burst
## (docs/01_VISUAL_DIRECTION.md). Small vs large is a scale/particle/duration
## difference only. Returns itself to the pool on expiry; never freed at runtime.

var release_callback: Callable = Callable()

var _age: float = 0.0
var _lifetime: float = 0.5
var _active: bool = false
var _major: bool = false
var _max_radius: float = 90.0
var _color: Color = Color(1.0, 0.48, 0.1)

@onready var _ring_sprite: Sprite2D = $RingSprite
@onready var _particles: CPUParticles2D = $Particles


## Activates the explosion. `is_major` picks the large preset; `particle_count`
## comes from the quality budget (0 disables the burst).
func spawn(world_pos: Vector2, is_major: bool, particle_count: int) -> void:
	global_position = world_pos
	_major = is_major
	_age = 0.0
	_active = true
	_lifetime = 0.6 if is_major else 0.4
	_max_radius = 150.0 if is_major else 80.0
	_color = Palette.get_color("orange", Color(1.0, 0.48, 0.1))
	visible = true
	set_process(true)

	if _ring_sprite != null:
		_ring_sprite.modulate = Color(_color, 0.9)
		_ring_sprite.scale = Vector2.ZERO
	if _particles != null:
		if particle_count > 0:
			_particles.amount = particle_count
			_particles.color = _color
			_particles.explosiveness = 1.0
			_particles.lifetime = _lifetime
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
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	if _ring_sprite != null:
		# Sprite ring is 1024px; scale it so it expands to ~2x max radius.
		var target := (_max_radius * 2.0) / 512.0
		_ring_sprite.scale = Vector2.ONE * lerpf(0.05, target, t)
		_ring_sprite.modulate.a = (1.0 - t) * 0.9
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	# Procedural expanding shock ring.
	var radius := lerpf(8.0, _max_radius, ease(t, 0.35))
	var alpha := 1.0 - t
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(_color, alpha * 0.8), (5.0 if _major else 3.0), true)
	# Light flash core, fades fast.
	var flash_a := clampf(1.0 - t * 2.5, 0.0, 1.0)
	if flash_a > 0.0:
		var core := (46.0 if _major else 26.0)
		draw_circle(Vector2.ZERO, core, Color(1, 1, 1, flash_a * 0.85))
		draw_circle(Vector2.ZERO, core * 1.7, Color(_color, flash_a * 0.4))


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
