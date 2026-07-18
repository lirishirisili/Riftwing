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
	if _flash_pool == null:
		return
	var node := _flash_pool.acquire() as HitFlash
	if node == null:
		return
	node.release_callback = Callable(_flash_pool, "release")
	node.spawn(world_pos, color, GameFeel.hit_spark_particles())


func spawn_explosion(world_pos: Vector2, is_major: bool) -> void:
	if _explosion_pool == null:
		return
	var node := _explosion_pool.acquire() as Explosion
	if node == null:
		return
	node.release_callback = Callable(_explosion_pool, "release")
	node.spawn(world_pos, is_major, GameFeel.explosion_particles(is_major))


func spawn_damage_number(world_pos: Vector2, amount: int) -> void:
	if _damage_pool == null:
		return
	var node := _damage_pool.acquire() as DamageNumber
	if node == null:
		return
	node.release_callback = Callable(_damage_pool, "release")
	node.spawn(world_pos, amount)


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
