class_name EffectsLayer
extends Node2D
## Owns the pooled effect nodes (hit flashes, explosions, damage numbers) for a
## gameplay scene and registers itself with GameFeel so intent calls route here.
##
## Effects render BELOW enemies and enemy bullets: this node sits at a low
## z_index while gameplay actors sit higher, so an explosion or flash can never
## paint over a dangerous enemy projectile (docs/07_QA_CHECKLIST.md: enemy
## bullets remain visible). All effect nodes are pooled and never freed at runtime.

## z_index kept well below gameplay actors so effects stay behind bullets.
const EFFECTS_Z_INDEX := -5

@export var hit_flash_scene: PackedScene
@export var explosion_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var hit_flash_prewarm: int = 48
@export var explosion_prewarm: int = 24
@export var damage_number_prewarm: int = 48
## Hard ceilings (-1 = 2× prewarm). Prevents effect storms from unbounded growth.
@export var hit_flash_max: int = -1
@export var explosion_max: int = -1
@export var damage_number_max: int = -1

var _flash_pool: ObjectPool
var _explosion_pool: ObjectPool
var _damage_pool: ObjectPool

## Lightning arcs: fixed slots drawn by this node (jagged polylines that fade).
const _MAX_ARCS := 10
const _ARC_LIFETIME := 0.22
const _ARC_SEGMENT := 34.0
var _arc_points: Array[PackedVector2Array] = []
var _arc_color: Array[Color] = []
var _arc_age := PackedFloat32Array()
var _arcs_live: int = 0


func _ready() -> void:
	z_index = EFFECTS_Z_INDEX
	z_as_relative = false
	if hit_flash_scene != null:
		_flash_pool = ObjectPool.new(hit_flash_scene, self, _cap(hit_flash_prewarm, hit_flash_max))
		_flash_pool.prewarm(hit_flash_prewarm)
	if explosion_scene != null:
		_explosion_pool = ObjectPool.new(explosion_scene, self, _cap(explosion_prewarm, explosion_max))
		_explosion_pool.prewarm(explosion_prewarm)
	if damage_number_scene != null:
		_damage_pool = ObjectPool.new(damage_number_scene, self, _cap(damage_number_prewarm, damage_number_max))
		_damage_pool.prewarm(damage_number_prewarm)
	for i in _MAX_ARCS:
		_arc_points.append(PackedVector2Array())
		_arc_color.append(Color.WHITE)
	_arc_age.resize(_MAX_ARCS)
	_arc_age.fill(_ARC_LIFETIME)
	add_to_group("pool_stats")
	GameFeel.register_effects_layer(self)


func _cap(prewarm: int, configured: int) -> int:
	if configured == 0:
		return 0
	if configured < 0:
		return maxi(prewarm * 2, prewarm)
	return configured


func _exit_tree() -> void:
	GameFeel.clear_sinks()


func spawn_hit_flash(world_pos: Vector2, color: Color) -> void:
	_spawn_flash(world_pos, color, GameFeel.hit_spark_particles(), HitFlash.Style.IMPACT)


func spawn_muzzle_flash(world_pos: Vector2, color: Color) -> void:
	# Muzzle is tiny + short — skip on LOW so mid-range devices stay clear.
	if GameFeel.quality == GameFeel.Quality.LOW:
		return
	_spawn_flash(world_pos, color, 0, HitFlash.Style.MUZZLE)


func spawn_shield_burst(world_pos: Vector2, color: Color) -> void:
	if GameFeel.quality == GameFeel.Quality.LOW:
		return
	_spawn_flash(world_pos, color, GameFeel.hit_spark_particles() / 2, HitFlash.Style.SHIELD)


func _spawn_flash(world_pos: Vector2, color: Color, sparks: int, style: int) -> void:
	if _flash_pool == null:
		return
	var node := _flash_pool.acquire() as HitFlash
	if node == null:
		return
	node.release_callback = Callable(_flash_pool, "release")
	node.spawn(world_pos, color, sparks, style)


func spawn_explosion(world_pos: Vector2, is_major: bool) -> void:
	if _explosion_pool == null:
		return
	var node := _explosion_pool.acquire() as Explosion
	if node == null:
		return
	node.release_callback = Callable(_explosion_pool, "release")
	node.spawn(world_pos, is_major, GameFeel.explosion_particles(is_major), GameFeel.explosion_debris(is_major))


## Colored ring burst (level-up, streak, chest, nova, boss kill). Shares the
## explosion pool so effect storms stay inside one hard cap.
func spawn_burst(world_pos: Vector2, color: Color, radius: float, lifetime: float) -> void:
	if _explosion_pool == null:
		return
	var node := _explosion_pool.acquire() as Explosion
	if node == null:
		return
	node.release_callback = Callable(_explosion_pool, "release")
	node.spawn_burst(world_pos, color, radius, lifetime)


## Jagged lightning through `points` (world space). Reuses the oldest slot.
func spawn_lightning(points: PackedVector2Array, color: Color) -> void:
	var slot := 0
	for i in _MAX_ARCS:
		if _arc_age[i] > _arc_age[slot]:
			slot = i
	var out := _arc_points[slot]
	out.clear()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(2, int(a.distance_to(b) / _ARC_SEGMENT))
		var normal := (b - a).orthogonal().normalized()
		for s in steps:
			var t := float(s) / float(steps)
			var jitter := 0.0 if s == 0 else randf_range(-16.0, 16.0)
			out.append(a.lerp(b, t) + normal * jitter)
	out.append(points[points.size() - 1])
	_arc_points[slot] = out
	_arc_color[slot] = color
	_arc_age[slot] = 0.0
	set_process(true)


func _process(delta: float) -> void:
	var live := 0
	for i in _MAX_ARCS:
		if _arc_age[i] < _ARC_LIFETIME:
			_arc_age[i] += delta
			live += 1
	if live > 0 or _arcs_live > 0:
		queue_redraw()
	_arcs_live = live
	if live == 0:
		set_process(false)


func _draw() -> void:
	for i in _MAX_ARCS:
		if _arc_age[i] >= _ARC_LIFETIME or _arc_points[i].size() < 2:
			continue
		var a := 1.0 - _arc_age[i] / _ARC_LIFETIME
		var c := _arc_color[i]
		# Drawn in world space: this layer sits at the world origin.
		draw_polyline(_arc_points[i], Color(c, 0.35 * a), 12.0, true)
		draw_polyline(_arc_points[i], Color(c, 0.9 * a), 4.0, true)
		draw_polyline(_arc_points[i], Color(1, 1, 1, a), 1.5, true)


func spawn_damage_number(world_pos: Vector2, amount: int, is_crit: bool = false) -> void:
	if _damage_pool == null:
		return
	var node := _damage_pool.acquire() as DamageNumber
	if node == null:
		return
	node.release_callback = Callable(_damage_pool, "release")
	node.spawn(world_pos, amount, is_crit)


## Live pool stats for the debug readout / pool_stats group.
func get_stats() -> Dictionary:
	return {
		"name": name,
		"flash_active": _flash_pool.get_active_count() if _flash_pool != null else 0,
		"flash_total": _flash_pool.get_total_count() if _flash_pool != null else 0,
		"flash_blocked": _flash_pool.get_blocked_acquires() if _flash_pool != null else 0,
		"explosion_active": _explosion_pool.get_active_count() if _explosion_pool != null else 0,
		"explosion_total": _explosion_pool.get_total_count() if _explosion_pool != null else 0,
		"explosion_blocked": _explosion_pool.get_blocked_acquires() if _explosion_pool != null else 0,
		"damage_active": _damage_pool.get_active_count() if _damage_pool != null else 0,
		"damage_total": _damage_pool.get_total_count() if _damage_pool != null else 0,
		"damage_blocked": _damage_pool.get_blocked_acquires() if _damage_pool != null else 0,
		"active": (
			(_flash_pool.get_active_count() if _flash_pool != null else 0)
			+ (_explosion_pool.get_active_count() if _explosion_pool != null else 0)
			+ (_damage_pool.get_active_count() if _damage_pool != null else 0)
		),
		"total": (
			(_flash_pool.get_total_count() if _flash_pool != null else 0)
			+ (_explosion_pool.get_total_count() if _explosion_pool != null else 0)
			+ (_damage_pool.get_total_count() if _damage_pool != null else 0)
		),
		"blocked": (
			(_flash_pool.get_blocked_acquires() if _flash_pool != null else 0)
			+ (_explosion_pool.get_blocked_acquires() if _explosion_pool != null else 0)
			+ (_damage_pool.get_blocked_acquires() if _damage_pool != null else 0)
		),
		"peak": 0,
		"max": 0,
		"growth": 0,
		"prewarm": hit_flash_prewarm + explosion_prewarm + damage_number_prewarm,
		"free": 0,
	}
