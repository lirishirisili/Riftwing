class_name ObjectPool
extends RefCounted
## Generic node pool over a single PackedScene.
##
## Nodes are instantiated up-front (prewarm) and parented under a holder. Pooled
## nodes stay in the tree; acquire enables one and moves it to the active set,
## release disables it and returns it to the free list. During normal use no
## node is ever freed, so there is no instantiate/free churn at runtime.
##
## Growth above prewarm is allowed only up to `max_total`. When the cap is hit,
## acquire() returns null so callers drop the spawn instead of unbounded OOM
## growth (mobile hardening).

var _scene: PackedScene
var _holder: Node
var _free: Array[Node] = []
var _active: Array[Node] = []
var _peak_active: int = 0
## Hard ceiling on active+free nodes. 0 = uncapped (legacy / stress tests).
var _max_total: int = 0
var _blocked_acquires: int = 0
var _growth_count: int = 0


func _init(scene: PackedScene, holder: Node, max_total: int = 0) -> void:
	_scene = scene
	_holder = holder
	_max_total = maxi(0, max_total)


## Instantiates `count` nodes up-front and parks them in the free list.
func prewarm(count: int) -> void:
	var target := count
	if _max_total > 0:
		target = mini(count, _max_total)
	for i in target:
		var node := _instantiate_disabled()
		if node == null:
			break
		_free.append(node)


## Returns a ready node from the free list, instantiating a new one only if the
## free list is empty and under the max_total cap. Returns null when capped out.
func acquire() -> Node:
	var node: Node
	if _free.is_empty():
		if _max_total > 0 and get_total_count() >= _max_total:
			_blocked_acquires += 1
			return null
		node = _instantiate_disabled()
		if node != null:
			_growth_count += 1
	else:
		node = _free.pop_back()
	if node == null:
		return null
	_active.append(node)
	_peak_active = maxi(_peak_active, _active.size())
	if node.has_method("pool_reset"):
		node.call("pool_reset")
	return node


## Disables a node and returns it to the free list for reuse.
func release(node: Node) -> void:
	var idx := _active.find(node)
	if idx == -1:
		return
	_active.remove_at(idx)
	if node.has_method("pool_disable"):
		node.call("pool_disable")
	else:
		_default_disable(node)
	_free.append(node)


## Releases every currently active node.
func release_all() -> void:
	for node in _active.duplicate():
		release(node)


func get_active_count() -> int:
	return _active.size()


func get_free_count() -> int:
	return _free.size()


func get_total_count() -> int:
	return _active.size() + _free.size()


func get_peak_active() -> int:
	return _peak_active


func get_max_total() -> int:
	return _max_total


func get_blocked_acquires() -> int:
	return _blocked_acquires


func get_growth_count() -> int:
	return _growth_count


func _instantiate_disabled() -> Node:
	if _scene == null:
		push_error("ObjectPool: scene is null")
		return null
	var node := _scene.instantiate()
	_holder.add_child(node)
	if node.has_method("pool_disable"):
		node.call("pool_disable")
	else:
		_default_disable(node)
	return node


func _default_disable(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is CanvasItem:
		(node as CanvasItem).visible = false
