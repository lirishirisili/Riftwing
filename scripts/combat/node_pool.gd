class_name NodePool
extends Node
## Scene-side generic pool node (enemies, pickups) built on ObjectPool.
##
## Mirrors ProjectilePool but stays type-agnostic. Growth is hard-capped by
## max_total for mobile memory safety.

@export var scene: PackedScene
@export var prewarm_count: int = 64
## Hard ceiling. -1 means 2× prewarm. 0 means uncapped.
@export var max_total: int = -1

var _pool: ObjectPool


func _ready() -> void:
	if scene == null:
		push_error("NodePool: scene not assigned")
		return
	var cap := _resolve_cap()
	_pool = ObjectPool.new(scene, self, cap)
	_pool.prewarm(prewarm_count)
	add_to_group("pool_stats")


func _resolve_cap() -> int:
	if max_total == 0:
		return 0
	if max_total < 0:
		return maxi(prewarm_count * 2, prewarm_count)
	return max_total


func acquire() -> Node:
	if _pool == null:
		return null
	return _pool.acquire()


func release(node: Node) -> void:
	if _pool != null:
		_pool.release(node)


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
