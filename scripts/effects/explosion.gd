class_name Explosion
extends Node2D
## Pooled explosion: combines a sprite ring (shockwave placeholder), a procedural
## expanding radial ring, a light flash, debris shards, and a CPU particle burst
## (docs/01_VISUAL_DIRECTION.md). Small vs large is a scale/particle/duration
## difference only. A "burst" variant (spawn_burst) is a pure colored ring used
## for level-ups, streaks, chests, the Rift Nova, and boss kills.
## Returns itself to the pool on expiry; never freed at runtime.

const _MAX_DEBRIS := 8

var release_callback: Callable = Callable()

var _age: float = 0.0
var _lifetime: float = 0.5
var _active: bool = false
var _major: bool = false
var _burst_only: bool = false
var _max_radius: float = 90.0
var _color: Color = Color(1.0, 0.48, 0.1)

# Debris shards: fixed-size buffers reused across spawns (no allocation).
var _debris_dir := PackedVector2Array()
var _debris_speed := PackedFloat32Array()
var _debris_count: int = 0

@onready var _ring_sprite: Sprite2D = $RingSprite
@onready var _particles: CPUParticles2D = $Particles


func _ready() -> void:
	_debris_dir.resize(_MAX_DEBRIS)
	_debris_speed.resize(_MAX_DEBRIS)


## Activates the explosion. `is_major` picks the large preset; `particle_count`
## comes from the quality budget (0 disables the burst).
func spawn(world_pos: Vector2, is_major: bool, particle_count: int, debris: int = 0) -> void:
	global_position = world_pos
	_major = is_major
	_burst_only = false
	_age = 0.0
	_active = true
	_lifetime = 0.65 if is_major else 0.38
	_max_radius = 160.0 if is_major else 72.0
	_color = Palette.get_color("magenta", Color(1.0, 0.22, 0.55)) if is_major \
		else Palette.get_color("orange", Color(1.0, 0.48, 0.1))
	visible = true
	set_process(true)
	_seed_debris(debris)

	if _ring_sprite != null:
		_ring_sprite.visible = true
		_ring_sprite.modulate = Color(_color, 0.85 if is_major else 0.75)
		_ring_sprite.scale = Vector2.ZERO
	if _particles != null:
		if particle_count > 0:
			_particles.amount = particle_count
			_particles.color = _color
			_particles.explosiveness = 1.0
			_particles.lifetime = _lifetime * 0.85
			_particles.emitting = true
		else:
			_particles.emitting = false
	queue_redraw()


## A colored expanding ring with a soft core and no particles/debris.
func spawn_burst(world_pos: Vector2, color: Color, radius: float, lifetime: float) -> void:
	global_position = world_pos
	_major = radius >= 200.0
	_burst_only = true
	_age = 0.0
	_active = true
	_lifetime = maxf(0.1, lifetime)
	_max_radius = maxf(20.0, radius)
	_color = color
	_debris_count = 0
	visible = true
	set_process(true)
	if _ring_sprite != null:
		_ring_sprite.visible = false
	if _particles != null:
		_particles.emitting = false
	queue_redraw()


func _seed_debris(count: int) -> void:
	_debris_count = clampi(count, 0, _MAX_DEBRIS)
	for i in _debris_count:
		var ang := TAU * (float(i) + randf_range(-0.3, 0.3)) / float(maxi(1, _debris_count))
		_debris_dir[i] = Vector2.RIGHT.rotated(ang)
		_debris_speed[i] = randf_range(0.7, 1.25)


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= _lifetime:
		_release()
		return
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	if _ring_sprite != null and _ring_sprite.visible:
		# Sprite ring is 1024px; scale it so it expands to ~2x max radius.
		var target := (_max_radius * 2.0) / 512.0
		_ring_sprite.scale = Vector2.ONE * lerpf(0.05, target, t)
		_ring_sprite.modulate.a = (1.0 - t) * 0.9
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var radius := lerpf(8.0, _max_radius, ease(t, 0.35))
	var alpha := 1.0 - t
	if _burst_only:
		# Double ring + inner glow; thin enough to keep bullets readable.
		var w := 10.0 if _major else 6.0
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(_color, alpha * 0.9), w, true)
		draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 48, Color(_color, alpha * 0.35), w * 0.5, true)
		var core_a := clampf(1.0 - t * 3.0, 0.0, 1.0)
		if core_a > 0.0:
			draw_circle(Vector2.ZERO, _max_radius * 0.18, Color(_color, core_a * 0.35))
		return
	# Procedural expanding shock ring + soft outer glow (kept behind bullets via layer z).
	draw_arc(Vector2.ZERO, radius * 1.08, 0.0, TAU, 40, Color(_color, alpha * 0.25), (10.0 if _major else 6.0), true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(_color, alpha * 0.85), (5.0 if _major else 3.0), true)
	# Debris shards: short hot streaks flung outward, decelerating.
	if _debris_count > 0:
		var travel := _max_radius * 1.25 * ease(t, 0.4)
		var shard_len := (18.0 if _major else 11.0) * (1.0 - t * 0.6)
		var hot := Color(1.0, 0.85, 0.55, alpha)
		for i in _debris_count:
			var d: Vector2 = _debris_dir[i]
			var p := d * travel * _debris_speed[i]
			draw_line(p, p - d * shard_len, hot, 3.0 if _major else 2.0, true)
	# Light flash core, fades fast.
	var flash_a := clampf(1.0 - t * 2.5, 0.0, 1.0)
	if flash_a > 0.0:
		var core := (50.0 if _major else 24.0)
		draw_circle(Vector2.ZERO, core, Color(1, 1, 1, flash_a * 0.9))
		draw_circle(Vector2.ZERO, core * 1.7, Color(_color, flash_a * 0.45))


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
