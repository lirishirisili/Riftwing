class_name ProjectilePool
extends Node
## Scene-side owner of a pooled set of Projectile nodes.
##
## Prewarms the pool on ready and exposes spawn() plus live statistics. All
## spawned projectiles are recycled through the pool; none are freed while the
## run is active. Growth is hard-capped by max_total for mobile memory safety.

@export var projectile_scene: PackedScene
@export var prewarm_count: int = 512
## Hard ceiling. -1 means 2× prewarm (safe default). 0 means uncapped (stress).
@export var max_total: int = -1
@export var despawn_bounds: Rect2 = Rect2(-200.0, -400.0, 1480.0, 2720.0)
@export var fires_at_player: bool = false

var _pool: ObjectPool
var _release_callable: Callable


func _ready() -> void:
	if projectile_scene == null:
		push_error("ProjectilePool: projectile_scene not assigned")
		return
	_release_callable = Callable(self, "_on_projectile_released")
	var cap := _resolve_cap()
	_pool = ObjectPool.new(projectile_scene, self, cap)
	_pool.prewarm(prewarm_count)
	add_to_group("pool_stats")


func _resolve_cap() -> int:
	if max_total == 0:
		return 0
	if max_total < 0:
		return maxi(prewarm_count * 2, prewarm_count)
	return max_total


func spawn(spawn_position: Vector2, direction: Vector2, data: ProjectileData) -> void:
	if _pool == null or data == null:
		return
	var node := _pool.acquire()
	var projectile := node as Projectile
	if projectile == null:
		return
	projectile.release_callback = _release_callable
	projectile.hits_player = fires_at_player
	projectile.launch(spawn_position, direction, data, despawn_bounds)


func release_all() -> void:
	if _pool != null:
		_pool.release_all()


func get_stats() -> Dictionary:
	if _pool == null:
		return {
			"name": name,
			"active": 0, "free": 0, "total": 0, "peak": 0,
			"prewarm": prewarm_count, "max": _resolve_cap(),
			"blocked": 0, "growth": 0,
		}
	return {
		"name": name,
		"active": _pool.get_active_count(),
		"free": _pool.get_free_count(),
		"total": _pool.get_total_count(),
		"peak": _pool.get_peak_active(),
		"prewarm": prewarm_count,
		"max": _pool.get_max_total(),
		"blocked": _pool.get_blocked_acquires(),
		"growth": _pool.get_growth_count(),
	}


func _on_projectile_released(projectile: Projectile) -> void:
	_pool.release(projectile)
